#ifndef AudioMixVolumeBoost_h
#define AudioMixVolumeBoost_h

#import <MediaToolbox/MediaToolbox.h>
#include <stdint.h>
#include <stdbool.h>

/// 已处理数据的观测值；输入/输出峰值保证来自同一块，其余计数和格式标记独立读取。
/// 峰值用于验证 PCM 增益，不代表扬声器响度。
typedef struct {
    /// 实际处理的累计帧数，不含格式不支持或源读取失败的块。
    uint64_t processedFrames;
    /// 从块开始到结束均为 2 倍时的累计帧数，不含过渡块。
    uint64_t boostedFrames;
    /// 最近一个块放大前的绝对峰值。
    float inputPeak;
    /// 最近一个块限幅后的绝对峰值，范围 0～1。
    float outputPeak;
    /// 当前协商格式是否在处理器支持范围内。
    bool supported;
    /// 已收到 prepare 且尚未 unprepare，区分等待加载和不支持格式。
    bool prepared;
} APVolumeBoostStats;

/// 原始 PCM 的 20ms 分窗观测；媒体时间来自 GetSourceAudio，不使用墙上时钟推测。
typedef struct {
    /// 当前窗口起止位置，单位为原始媒体秒；负值表示时间不连续或未知。
    double start, end;
    /// 所有声道 RMS 的最大值与所有样本峰值，均在增益处理前计算。
    double rms, peak;
    /// 系统音频不连续时递增；消费端必须清理上一段的候选区间。
    uint64_t streamID;
    /// 主线程取消代次；用于排除 seek/停止前已经进入回调的旧结果。
    uint32_t generation;
} APSilenceWindow;

/// 默认不分析静音；由独立案例主线程启停，不影响增益开关。
void APVolumeBoostSetSilenceDetection(MTAudioProcessingTapRef _Nonnull tap, bool enabled);
/// 单生产者单消费者队列：仅主线程读取，同一个 tap 不允许有多个读取方。
uint32_t APVolumeBoostReadSilence(MTAudioProcessingTapRef _Nonnull tap, APSilenceWindow * _Nonnull output, uint32_t capacity);
/// 主线程请求重置检测代次；不操作音频线程的累积字段，也不改变增益目标。
uint32_t APVolumeBoostResetSilence(MTAudioProcessingTapRef _Nonnull tap);

/// 创建独立 tap；返回对象由调用方释放，处理状态由 tap 的 finalize 回收。
MTAudioProcessingTapRef _Nullable APVolumeBoostCreateTap(void) CF_RETURNS_RETAINED;
/// 只发布 1 倍或 2 倍目标；音频线程无锁读取，并在一个音频块内平滑过渡。
void APVolumeBoostSetEnabled(MTAudioProcessingTapRef _Nonnull tap, bool enabled);
/// 从原子字段读取统计，不在实时线程调用日志或 UI。
APVolumeBoostStats APVolumeBoostGetStats(MTAudioProcessingTapRef _Nonnull tap);
/// 已分配且尚未 finalize 的 tap 状态数，用于生命周期回归。
uint32_t APVolumeBoostLiveContexts(void);

#endif
