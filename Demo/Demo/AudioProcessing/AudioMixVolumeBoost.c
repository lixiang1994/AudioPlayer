#include "AudioMixVolumeBoost.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <limits.h>

/// 回调只使用平台保证无锁的整型原子；音频线程不分配、不加锁、不调用 Swift。
_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LLONG_LOCK_FREE == 2, "需要无锁整型原子");
/// 每个 tap 独立持有状态；format/currentGain 仅由串行音频回调访问，其余字段跨线程发布。
typedef struct {
    /// 主线程发布的目标，只取 1 或 2；音频线程在块边界读取。
    atomic_uint targetGain;
    /// 回调累计处理的帧数，由 UI 读取用于验证处理确实发生。
    atomic_ullong processedFrames;
    /// 已稳定达到 2 倍增益的帧数，排除平滑过渡块。
    atomic_ullong boostedFrames;
    /// 最近块输入峰值的 Float32 位模式。
    atomic_uint inputPeakBits;
    /// 最近块输出峰值的 Float32 位模式，与输入统计仅作观测。
    atomic_uint outputPeakBits;
    /// 当前格式是否可处理，不支持时只拉取源音频并旁路。
    atomic_uint supported;
    /// prepare/unprepare 生命周期标记，不代表已经处理过 PCM。
    atomic_uint prepared;
    /// 仅系统串行 prepare/process 回调使用的当前 PCM 格式。
    AudioStreamBasicDescription format;
    /// 上一个块的最终增益，供本块平滑衔接，仅音频线程访问。
    float currentGain;
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
    atomic_init(&context->inputPeakBits, 0);
    atomic_init(&context->outputPeakBits, 0);
    atomic_init(&context->supported, 0);
    atomic_init(&context->prepared, 0);
    context->currentGain = 1;
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

/// 拉取系统 PCM 后原地放大，按块平滑切换增益，并限制在 [-1, 1] 防止数值溢出。
static void process(MTAudioProcessingTapRef tap, CMItemCount requestedFrames, MTAudioProcessingTapFlags flags,
                    AudioBufferList *buffers, CMItemCount *framesOut, MTAudioProcessingTapFlags *flagsOut) {
    *framesOut = 0;
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, requestedFrames, buffers, flagsOut, NULL, framesOut);
    APVolumeBoostContext *context = MTAudioProcessingTapGetStorage(tap);
    if (status != noErr || *framesOut <= 0 || !context ||
        !atomic_load_explicit(&context->supported, memory_order_relaxed)) return;
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
    atomic_store_explicit(&context->inputPeakBits, peakBits(inputPeak), memory_order_relaxed);
    atomic_store_explicit(&context->outputPeakBits, peakBits(outputPeak), memory_order_relaxed);
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
    unsigned int input = atomic_load_explicit(&context->inputPeakBits, memory_order_relaxed);
    unsigned int output = atomic_load_explicit(&context->outputPeakBits, memory_order_relaxed);
    memcpy(&stats.inputPeak, &input, sizeof(input));
    memcpy(&stats.outputPeak, &output, sizeof(output));
    stats.supported = atomic_load_explicit(&context->supported, memory_order_relaxed);
    stats.prepared = atomic_load_explicit(&context->prepared, memory_order_relaxed);
    return stats;
}

uint32_t APVolumeBoostLiveContexts(void) {
    return atomic_load_explicit(&liveContexts, memory_order_relaxed);
}
