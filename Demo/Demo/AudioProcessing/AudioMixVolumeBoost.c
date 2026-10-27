#include "AudioMixVolumeBoost.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <limits.h>

/// 回调只使用平台保证无锁的整型原子；音频线程不分配、不加锁、不调用 Swift。
_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LLONG_LOCK_FREE == 2, "需要无锁整型原子");
/// 固定容量约容纳 40 秒检测窗；满时丢弃新观测，不能阻塞音频输出。
#define AP_SILENCE_CAPACITY 2048
/// 检测最多支持 32 声道；超过时只保留原有增益功能，不猜测未检查声道。
#define AP_SILENCE_CHANNELS 32
/// 每个 tap 独立持有状态；format/currentGain 仅由串行音频回调访问，其余字段跨线程发布。
typedef struct {
    /// 主线程发布的目标，只取 1 或 2；音频线程在块边界读取。
    atomic_uint targetGain;
    /// 回调累计处理的帧数，由 UI 读取用于验证处理确实发生。
    atomic_ullong processedFrames;
    /// 已稳定达到 2 倍增益的帧数，排除平滑过渡块。
    atomic_ullong boostedFrames;
    /// 同一块输入和输出峰值的 Float32 位模式；一次发布，防止主线程读到跨块比值。
    atomic_ullong peakPairBits;
    /// 当前格式是否可处理，不支持时只拉取源音频并旁路。
    atomic_uint supported;
    /// prepare/unprepare 生命周期标记，不代表已经处理过 PCM。
    atomic_uint prepared;
    /// 仅系统串行 prepare/process 回调使用的当前 PCM 格式。
    AudioStreamBasicDescription format;
    /// 上一个块的最终增益，供本块平滑衔接，仅音频线程访问。
    float currentGain;
    /// 音频线程写、主线程读；release/acquire 保证槽位完整后才可读取或复用。
    APSilenceWindow silence[AP_SILENCE_CAPACITY];
    atomic_uint silenceWrite, silenceRead, silenceGeneration, silenceEnabled;
    /// 以下检测累积字段只在系统串行音频回调内访问，主线程仅请求代次重置。
    uint32_t detectorGeneration, windowFrames;
    uint64_t streamID;
    double energy[AP_SILENCE_CHANNELS], windowPeak, windowStart, expectedTime;
} APVolumeBoostContext;
/// 只统计处理状态，不持有 tap，便于确认反复切换资源后没有遗留分配。
static atomic_uint liveContexts = 0;

/// 浮点峰值以位模式发布，避免依赖浮点原子的锁实现。
static unsigned int peakBits(float peak) {
    unsigned int bits;
    memcpy(&bits, &peak, sizeof(bits));
    return bits;
}

/// 在创建阶段分配状态；所有原子显式初始化，默认旁路为 1 倍。
static void initialize(MTAudioProcessingTapRef tap, void *clientInfo, void **storage) {
    APVolumeBoostContext *context = calloc(1, sizeof(*context));
    *storage = context;
    if (!context) return;
    atomic_init(&context->targetGain, 1);
    atomic_init(&context->processedFrames, 0);
    atomic_init(&context->boostedFrames, 0);
    atomic_init(&context->peakPairBits, 0);
    atomic_init(&context->supported, 0);
    atomic_init(&context->prepared, 0);
    context->currentGain = 1;
    atomic_init(&context->silenceWrite, 0);
    atomic_init(&context->silenceRead, 0);
    atomic_init(&context->silenceGeneration, 1);
    atomic_init(&context->silenceEnabled, 0);
    context->expectedTime = -1;
    atomic_fetch_add_explicit(&liveContexts, 1, memory_order_relaxed);
}

/// tap 最后一个引用释放后回收状态；UI 不直接销毁仍在使用的处理数据。
static void finalize(MTAudioProcessingTapRef tap) {
    void *context = MTAudioProcessingTapGetStorage(tap);
    if (!context) return;
    free(context);
    atomic_fetch_sub_explicit(&liveContexts, 1, memory_order_relaxed);
}

/// 仅处理原生字节序的紧密排列 Float32/Int16/Int32 PCM；其他格式保留原样并报告未支持。
static void prepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *format) {
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (!context) return;
    context->format = *format;
    context->expectedTime = -1;
    context->windowFrames = 0;
    atomic_store_explicit(&context->prepared, 1, memory_order_relaxed);
    unsigned int flags = format->mFormatFlags;
    bool linear = format->mFormatID == kAudioFormatLinearPCM &&
        (flags & kAudioFormatFlagIsPacked) && !(flags & kAudioFormatFlagIsBigEndian);
    bool floating = (flags & kAudioFormatFlagIsFloat) && format->mBitsPerChannel == 32;
    bool integer = (flags & kAudioFormatFlagIsSignedInteger) &&
        (format->mBitsPerChannel == 16 || format->mBitsPerChannel == 32);
    atomic_store_explicit(&context->supported, linear && (floating || integer), memory_order_relaxed);
}

/// 系统可重新协商格式；下一次 prepare 前不继续使用旧格式处理。
static void unprepare(MTAudioProcessingTapRef tap) {
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (context) {
        atomic_store_explicit(&context->supported, 0, memory_order_relaxed);
        atomic_store_explicit(&context->prepared, 0, memory_order_relaxed);
    }
}

/// 将完整观测发布到固定队列；队列满时留出时间缺口，让消费端保守退出加速。
static void publishSilence(APVolumeBoostContext *context, APSilenceWindow window) {
    unsigned int write = atomic_load_explicit(&context->silenceWrite, memory_order_relaxed);
    unsigned int read = atomic_load_explicit(&context->silenceRead, memory_order_acquire);
    if ((unsigned int)(write - read) >= AP_SILENCE_CAPACITY) return;
    context->silence[write % AP_SILENCE_CAPACITY] = window;
    atomic_store_explicit(&context->silenceWrite, write + 1, memory_order_release);
}

/// 仅音频线程清空跨块累积；增益与静音检测独立，不重置 targetGain。
static void resetDetector(APVolumeBoostContext *context, uint32_t generation) {
    context->detectorGeneration = generation;
    context->streamID++;
    context->windowFrames = 0;
    context->windowPeak = 0;
    memset(context->energy, 0, sizeof(context->energy));
    context->expectedTime = -1;
}

/// 在任何放大前读取原始 PCM；跨缓冲积累每声道 RMS，防止单声道有人声被平均稀释。
static void analyzeSilence(APVolumeBoostContext *context, AudioBufferList *buffers, CMItemCount frames,
                           CMTimeRange range, MTAudioProcessingTapFlags flags, uint32_t generation) {
    double start = CMTimeGetSeconds(range.start), duration = CMTimeGetSeconds(range.duration);
    if (!isfinite(start) || !isfinite(duration) || start < 0 || duration <= 0 ||
        context->format.mChannelsPerFrame > AP_SILENCE_CHANNELS || context->format.mSampleRate <= 0) {
        resetDetector(context, generation);
        publishSilence(context, (APSilenceWindow){ .start = -1, .end = -1, .streamID = context->streamID, .generation = generation });
        return;
    }
    if (context->detectorGeneration != generation || (flags & kMTAudioProcessingTapFlag_StartOfStream) ||
        context->expectedTime < 0 || fabs(start - context->expectedTime) > 0.003) resetDetector(context, generation);
    unsigned int bits = context->format.mBitsPerChannel;
    bool floating = context->format.mFormatFlags & kAudioFormatFlagIsFloat;
    uint32_t windowSize = (uint32_t)fmax(1, round(context->format.mSampleRate * 0.02));
    for (CMItemCount frame = 0; frame < frames; frame++) {
        if (context->windowFrames == 0) context->windowStart = start + duration * frame / frames;
        unsigned int channel = 0;
        bool complete = true;
        for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
            AudioBuffer buffer = buffers->mBuffers[b];
            for (UInt32 c = 0; c < buffer.mNumberChannels; c++, channel++) {
                size_t index = (size_t)frame * buffer.mNumberChannels + c;
                if (channel >= AP_SILENCE_CHANNELS || !buffer.mData || (index + 1) * (bits / 8) > buffer.mDataByteSize) {
                    complete = false;
                    continue;
                }
                double value = floating ? ((float *)buffer.mData)[index] : bits == 16 ?
                    ((int16_t *)buffer.mData)[index] / 32768.0 : ((int32_t *)buffer.mData)[index] / 2147483648.0;
                // 非有限样本属于未知声音，不允许作为静音证据。
                if (!isfinite(value)) { complete = false; value = 1; }
                context->energy[channel] += value * value;
                context->windowPeak = fmax(context->windowPeak, fabs(value));
            }
        }
        if (!complete || channel != context->format.mChannelsPerFrame) context->windowPeak = 1;
        context->windowFrames++;
        if (context->windowFrames >= windowSize) {
            double maximumEnergy = 0;
            for (unsigned int c = 0; c < AP_SILENCE_CHANNELS; c++) maximumEnergy = fmax(maximumEnergy, context->energy[c]);
            APSilenceWindow window = { .start = context->windowStart, .end = start + duration * (frame + 1) / frames,
                .rms = sqrt(maximumEnergy / context->windowFrames), .peak = context->windowPeak,
                .streamID = context->streamID, .generation = generation };
            publishSilence(context, window);
            context->windowFrames = 0;
            context->windowPeak = 0;
            memset(context->energy, 0, sizeof(context->energy));
        }
    }
    context->expectedTime = start + duration;
}

/// 拉取系统 PCM 后原地放大，按块平滑切换增益，并限制在 [-1, 1] 防止数值溢出。
static void process(MTAudioProcessingTapRef tap, CMItemCount requestedFrames, MTAudioProcessingTapFlags flags,
                    AudioBufferList *buffers, CMItemCount *framesOut, MTAudioProcessingTapFlags *flagsOut) {
    *framesOut = 0;
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    // 拉取前捕获代次，避免主线程 seek 期间完成的旧读取被标记为新结果。
    uint32_t generation = context ? atomic_load_explicit(&context->silenceGeneration, memory_order_acquire) : 0;
    CMTimeRange range = kCMTimeRangeInvalid;
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, requestedFrames, buffers, flagsOut, &range, framesOut);
    if (status != noErr || *framesOut <= 0 || !context ||
        !atomic_load_explicit(&context->supported, memory_order_relaxed)) return;
    if (atomic_load_explicit(&context->silenceEnabled, memory_order_relaxed))
        analyzeSilence(context, buffers, *framesOut, range, *flagsOut, generation);
    float target = (float)atomic_load_explicit(&context->targetGain, memory_order_relaxed);
    float start = context->currentGain;
    float inputPeak = 0, outputPeak = 0;
    unsigned int bits = context->format.mBitsPerChannel;
    bool floating = context->format.mFormatFlags & kAudioFormatFlagIsFloat;
    for (UInt32 bufferIndex = 0; bufferIndex < buffers->mNumberBuffers; bufferIndex++) {
        AudioBuffer buffer = buffers->mBuffers[bufferIndex];
        if (!buffer.mData || !buffer.mNumberChannels) continue;
        // 同时支持交错和非交错 PCM，并用实际字节数约束访问范围。
        size_t samples = buffer.mDataByteSize / (bits / 8);
        size_t expected = (size_t)*framesOut * buffer.mNumberChannels;
        if (samples > expected) samples = expected;
        for (size_t index = 0; index < samples; index++) {
            float gain = start + (target - start) * (float)(index / buffer.mNumberChannels + 1) / (float)*framesOut;
            float input;
            if (floating) input = ((float *)buffer.mData)[index];
            else if (bits == 16) input = ((int16_t *)buffer.mData)[index] / 32768.0f;
            else input = (float)(((int32_t *)buffer.mData)[index] / 2147483648.0);
            if (!isfinite(input)) input = 0;
            float output = fmaxf(-1, fminf(1, input * gain));
            inputPeak = fmaxf(inputPeak, fabsf(input));
            outputPeak = fmaxf(outputPeak, fabsf(output));
            if (floating) ((float *)buffer.mData)[index] = output;
            else if (bits == 16) ((int16_t *)buffer.mData)[index] = (int16_t)fmax(-32768.0, fmin(32767.0, (double)output * 32768.0));
            else ((int32_t *)buffer.mData)[index] = (int32_t)fmax(-2147483648.0, fmin(2147483647.0, (double)output * 2147483648.0));
        }
    }
    context->currentGain = target;
    // 两个峰值组成一个无锁快照；无需依赖其他统计字段的可见顺序。
    unsigned long long pair = ((unsigned long long)peakBits(inputPeak) << 32) | peakBits(outputPeak);
    atomic_store_explicit(&context->peakPairBits, pair, memory_order_relaxed);
    atomic_fetch_add_explicit(&context->processedFrames, *framesOut, memory_order_relaxed);
    if (target == 2 && start == 2) atomic_fetch_add_explicit(&context->boostedFrames, *framesOut, memory_order_relaxed);
}

MTAudioProcessingTapRef APVolumeBoostCreateTap(void) {
    MTAudioProcessingTapRef tap = NULL;
    // SDK 的回调结构按 4 字节打包；逐字段赋值避免 arm64 链接器对常量函数指针的对齐错误。
    MTAudioProcessingTapCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
    callbacks.init = initialize;
    callbacks.finalize = finalize;
    callbacks.prepare = prepare;
    callbacks.unprepare = unprepare;
    callbacks.process = process;
    OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
    if (status != noErr) return NULL;
    if (!MTAudioProcessingTapGetStorage(tap)) { CFRelease(tap); return NULL; }
    return tap;
}

void APVolumeBoostSetEnabled(MTAudioProcessingTapRef tap, bool enabled) {
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (context) atomic_store_explicit(&context->targetGain, enabled ? 2 : 1, memory_order_relaxed);
}

APVolumeBoostStats APVolumeBoostGetStats(MTAudioProcessingTapRef tap) {
    APVolumeBoostStats stats = {0};
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (!context) return stats;
    stats.processedFrames = atomic_load_explicit(&context->processedFrames, memory_order_relaxed);
    stats.boostedFrames = atomic_load_explicit(&context->boostedFrames, memory_order_relaxed);
    // 只读取一次，随后在本地拆包；各帧计数仍是独立观测，不承诺整份统计同一时刻。
    unsigned long long pair = atomic_load_explicit(&context->peakPairBits, memory_order_relaxed);
    unsigned int input = (unsigned int)(pair >> 32);
    unsigned int output = (unsigned int)pair;
    memcpy(&stats.inputPeak, &input, sizeof(input));
    memcpy(&stats.outputPeak, &output, sizeof(output));
    stats.supported = atomic_load_explicit(&context->supported, memory_order_relaxed);
    stats.prepared = atomic_load_explicit(&context->prepared, memory_order_relaxed);
    return stats;
}

uint32_t APVolumeBoostLiveContexts(void) {
    return atomic_load_explicit(&liveContexts, memory_order_relaxed);
}

uint32_t APVolumeBoostReadSilence(MTAudioProcessingTapRef tap, APSilenceWindow *output, uint32_t capacity) {
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (!context) return 0;
    unsigned int read = atomic_load_explicit(&context->silenceRead, memory_order_relaxed);
    unsigned int write = atomic_load_explicit(&context->silenceWrite, memory_order_acquire);
    uint32_t count = (uint32_t)(write - read);
    if (count > capacity) count = capacity;
    for (uint32_t i = 0; i < count; i++) output[i] = context->silence[(read + i) % AP_SILENCE_CAPACITY];
    atomic_store_explicit(&context->silenceRead, read + count, memory_order_release);
    return count;
}

uint32_t APVolumeBoostResetSilence(MTAudioProcessingTapRef tap) {
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    return context ? atomic_fetch_add_explicit(&context->silenceGeneration, 1, memory_order_acq_rel) + 1 : 0;
}

void APVolumeBoostSetSilenceDetection(MTAudioProcessingTapRef tap, bool enabled) {
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (context) atomic_store_explicit(&context->silenceEnabled, enabled, memory_order_relaxed);
}
