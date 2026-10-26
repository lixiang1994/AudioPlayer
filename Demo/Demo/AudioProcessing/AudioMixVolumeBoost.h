#ifndef AudioMixVolumeBoost_h
#define AudioMixVolumeBoost_h

#import <MediaToolbox/MediaToolbox.h>
#include <stdint.h>
#include <stdbool.h>

/// 已处理数据的观测快照；峰值为最近一个音频块，用于验证 PCM 增益而非扬声器响度。
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

/// 创建独立 tap；返回对象由调用方释放，处理状态由 tap 的 finalize 回收。
MTAudioProcessingTapRef _Nullable APVolumeBoostCreateTap(void) CF_RETURNS_RETAINED;
/// 只发布 1 倍或 2 倍目标；音频线程无锁读取，并在一个音频块内平滑过渡。
void APVolumeBoostSetEnabled(MTAudioProcessingTapRef _Nonnull tap, bool enabled);
/// 从原子字段读取统计，不在实时线程调用日志或 UI。
APVolumeBoostStats APVolumeBoostGetStats(MTAudioProcessingTapRef _Nonnull tap);
/// 已分配且尚未 finalize 的 tap 状态数，用于生命周期回归。
uint32_t APVolumeBoostLiveContexts(void);

#endif
