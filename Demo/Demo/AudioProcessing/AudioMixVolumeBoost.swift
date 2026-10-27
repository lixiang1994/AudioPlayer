import AVFoundation
import MediaToolbox
import AudioPlayer

/// Demo 专用增强处理器；每条音轨持有独立 tap，切换只更新无锁目标增益，不重建 mix。
final class AudioMixVolumeBoost {
    /// 绑定当前 asset 音轨的混合配置，从原始音量开始旁路处理。
    let mix: AVAudioMix
    /// Swift 与 AVAudioMix 都持有 tap；C 状态在最后一个引用释放时 finalize。
    private let taps: [MTAudioProcessingTap]
    /// UI 所选目标；音频线程只消费 C 原子字段，不读取 Swift 属性。
    private(set) var isEnabled = false

    /// 主线程消费的检测时间线；单音轨包含多个声道，多音轨暂保守禁用静音加速。
    private(set) var silenceTimeline = AudioMixSilenceTimeline()
    /// 检测的独立运行状态；默认关闭，关闭后不再消费或计算静音窗口。
    private(set) var isSilenceDetectionEnabled = false
    /// 主线程取消代次，与 C 回调已发布窗口逐个比对。
    private var silenceGeneration: UInt32 = 1

    /// 开始/停止观测与音量增强无关；仅独立案例使用，不增加主播放页的检测开销。
    func setSilenceDetection(_ enabled: Bool) {
        guard isSilenceDetectionEnabled != enabled else { return }
        isSilenceDetectionEnabled = enabled
        // 先使旧代次失效，再发布运行状态；已在音频线程执行的旧块不能恢复旧时间线。
        resetSilenceDetection()
        taps.forEach { APVolumeBoostSetSilenceDetection($0, enabled) }
    }

    /// seek 前及完成后清理候选，不把旧资源、旧位置的分析结果用于加速。
    func resetSilenceDetection() {
        silenceTimeline.reset()
        for tap in taps { silenceGeneration = APVolumeBoostResetSilence(tap) }
    }

    /// 仅主线程读取固定队列；每轮有界排空，多音轨无法证明所有轨道安静时不加速。
    func collectSilenceWindows() {
        guard isSilenceDetectionEnabled, taps.count == 1, let tap = taps.first, isSupported else { silenceTimeline.reset(); return }
        var windows = [APSilenceWindow](repeating: APSilenceWindow(), count: 128)
        for _ in 0..<16 {
            let count = windows.withUnsafeMutableBufferPointer { APVolumeBoostReadSilence(tap, $0.baseAddress!, UInt32($0.count)) }
            for window in windows.prefix(Int(count)) where window.generation == silenceGeneration {
                silenceTimeline.append(start: window.start, end: window.end, rms: window.rms, peak: window.peak, streamID: window.streamID)
            }
            if count < 128 { break }
        }
    }

    /// 所有音轨已处理的帧数，证明系统实际执行过 PCM 回调。
    var processedFrames: UInt64 { taps.reduce(0) { $0 + APVolumeBoostGetStats($1).processedFrames } }
    /// 稳定在 2 倍增益时处理的帧数，不含切换过渡块。
    var boostedFrames: UInt64 { taps.reduce(0) { $0 + APVolumeBoostGetStats($1).boostedFrames } }
    /// 第一条音轨最近一个数据块的峰值比；用于低振幅测试，静音时返回 nil。
    var measuredGain: Float? {
        guard let tap = taps.first else { return nil }
        let stats = APVolumeBoostGetStats(tap)
        guard stats.inputPeak > 0.000001 else { return nil }
        return stats.outputPeak / stats.inputPeak
    }
    /// 最近一个块的输出峰值，限幅测试要求不超过 1；音频回调尚未运行时为 0。
    var outputPeak: Float { taps.map { APVolumeBoostGetStats($0).outputPeak }.max() ?? 0 }
    /// 已有格式协商时可区分等待准备与不支持格式，避免界面把旁路误报为增强。
    var hasPreparedFormat: Bool { taps.contains { APVolumeBoostGetStats($0).prepared } }
    /// 格式是否已经协商且所有音轨均可处理；未准备时为 false。
    var isSupported: Bool { !taps.isEmpty && taps.allSatisfy { APVolumeBoostGetStats($0).supported } }
    /// 用于反复创建/销毁回归，不保留任何 tap 或处理状态。
    static var liveContexts: UInt32 { APVolumeBoostLiveContexts() }

    /// 音轨由外部异步加载；这里仅建立处理链，不做文件或网络访问。
    init(tracks: [AVAssetTrack]) throws {
        guard !tracks.isEmpty else {
            throw NSError(domain: "AudioMixVolumeBoost", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可处理的音轨"])
        }
        taps = try tracks.map { _ in
            guard let tap = APVolumeBoostCreateTap() else {
                throw NSError(domain: "AudioMixVolumeBoost", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建增强处理器"])
            }
            return tap
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = zip(tracks, taps).map { track, tap in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            return parameters
        }
        self.mix = mix
    }

    /// 主线程发布新目标，音频线程在一个数据块内平滑切换；不 seek、pause 或修改 item。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        taps.forEach { APVolumeBoostSetEnabled($0, enabled) }
    }
}
