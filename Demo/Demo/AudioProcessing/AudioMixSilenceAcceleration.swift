import AVFoundation
import AudioPlayer

/// 主线程维护的原始媒体时间线；仅使用当前位置附近的新鲜静音观测，不预测未知未来。
struct AudioMixSilenceTimeline {
    /// 已确认或仍在延伸的安静区间；最多保留 256 段，避免长音频持续增长。
    private(set) var ranges: [ClosedRange<Double>] = []
    /// 最新连续数据的终点，单位媒体秒，不代表播放器已经听到该位置。
    private(set) var analyzedUntil: Double = 0
    /// 任意有声窗口都会递增，重置时间线也不回退；防止同批后续静音掩盖短暂声音。
    private(set) var soundGeneration: UInt64 = 0
    /// 连续证据代次；流切换、丢窗和主动清理都会递增，旧许可不能跨缺口使用。
    private(set) var continuityGeneration: UInt64 = 0
    /// 最新观测到达的单调时钟秒；媒体进度冻结时仍能按真实经过时间淘汰旧证据。
    private var lastObservationTime: TimeInterval?
    /// 最后一个窗口所属流，不连续或重新协商格式时必须重新积累。
    private var streamID: UInt64?
    /// 当前候选的开头；nil 表示有声或证据不足。
    private var candidateStart: Double?

    /// 清除媒体时间证据，不改变 UI 的功能偏好。
    mutating func reset() {
        continuityGeneration &+= 1
        ranges = []
        analyzedUntil = 0
        lastObservationTime = nil
        streamID = nil
        candidateStart = nil
    }

    /// 进入阈值为 RMS -60dBFS，退出阈值略高；峰值约束保护瞬态与轻声边缘。
    /// start/end 使用原始媒体秒，observedAt 使用单调时钟秒，可注入以确定性验证过期。
    mutating func append(start: Double, end: Double, rms: Double, peak: Double, streamID: UInt64, observedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard start.isFinite, end.isFinite, rms.isFinite, peak.isFinite, observedAt.isFinite, start >= 0, end > start else { reset(); return }
        if self.streamID != streamID || abs(start - analyzedUntil) > 0.003 { reset() }
        self.streamID = streamID
        lastObservationTime = observedAt
        let quiet = rms <= (candidateStart == nil ? 0.001 : 0.0015) && peak <= 0.004
        if quiet {
            let beginning = candidateStart ?? start
            candidateStart = beginning
            // 至少连续安静 300ms 才保留候选；每个窗口延长上限，永不把未知未来算作安静。
            if end - beginning >= 0.3 {
                if ranges.last?.lowerBound == beginning { ranges[ranges.count - 1] = beginning...end }
                else { ranges.append(beginning...end) }
                if ranges.count > 256 { ranges.removeFirst(ranges.count - 256) }
            }
        } else {
            candidateStart = nil
            soundGeneration &+= 1
        }
        analyzedUntil = end
    }

    /// 最新有效窗口明确有声时，速率切换保护也必须立即退出，不能把已知人声当成重配置空档。
    var hasNonQuietObservation: Bool { lastObservationTime != nil && candidateStart == nil }

    /// 连续安静 300ms 媒体时间后提速；延续加速必须同时匹配有声和连续证据代次，新声音或时间缺口都会要求重新确认。
    /// 当前位置必须落在该连续静音段内；允许最新窗口最多落后 100ms，不因解码前瞻较多而误判过期。
    /// now 使用与 observedAt 相同的单调时钟；观测超过 250ms 即失效，媒体时钟冻结也不能延长许可。
    /// tap 无固定前瞻保证，检测与控制存在延迟，不能保证语音起点完全不被加速。
    func canAccelerate(at time: Double, continuingAfter soundGeneration: UInt64? = nil, continuingIn continuityGeneration: UInt64? = nil, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard time.isFinite, now.isFinite, let observedAt = lastObservationTime,
              now >= observedAt, now - observedAt <= 0.25 else { return false }
        guard let beginning = candidateStart else { return false }
        let continuous = soundGeneration == self.soundGeneration && continuityGeneration == self.continuityGeneration
        let confirmation = continuous ? 0.0 : 0.3
        return analyzedUntil - beginning >= confirmation && time >= beginning + confirmation &&
            time <= analyzedUntil + 0.1
    }
}

/// Demo 的临时倍率策略；能力未知时保持用户倍速，避免猜测当前 item 的支持范围。
enum AudioMixSilenceRatePolicy {
    /// 静音优先使用 3×，系统不支持超过 2× 时回退到 2×。
    /// 入场至少保留两秒实际播放余量，已加速时低于半秒余量退出；滞回避免临界缓冲频繁切速。
    /// 完整本地资源及已缓冲至结尾的尾段无需满足时长门槛；网络仍可能在之后变慢。
    static func target(userRate: Double, capacity: AVAudioPlaybackCapacity?, continuing: Bool) -> Double {
        guard let capacity = capacity else { return userRate }
        let target = capacity.canPlayFastForward ? 3.0 : 2.0
        let required = target * (continuing ? 0.5 : 2)
        guard capacity.bufferedDuration.isFinite, capacity.bufferedDuration >= 0,
              capacity.isBufferedToEnd || capacity.bufferedDuration >= required else { return userRate }
        return max(userRate, target)
    }
}

/// 独立 Demo 的倍速仲裁；用户倍速与临时加速分开，不接管主播放页或锁屏。
final class AudioMixSilenceAcceleration: NSObject, AudioPlayerDelegate {
    /// 独立播放器；所有控制限定主线程，由页面持有本控制器。
    private let player: AudioPlayerable
    /// 页面持有处理器，控制器弱引用，避免延长 tap 的释放周期。
    private weak var processor: AudioMixVolumeBoost?
    /// 主 RunLoop 每 40ms 根据媒体时间决策，回调弱持有自己。
    private var timer: Timer?
    /// 上次加速决策已知的有声代次；本轮批量读取出现过新声音时，不允许沿用旧许可。
    private var acceleratingSoundGeneration: UInt64?
    /// 上次许可的连续证据代次；普通断流不能沿用旧段静音，调速保护仅在自身过渡期内适用。
    private var acceleratingContinuityGeneration: UInt64?
    /// 自己设置速率会触发 tap 短暂 unprepare；仅允许最多 250ms 的重配置空档，防止速率来回震荡。
    private var rateTransitionDeadline: TimeInterval?
    /// seek 期间即使 control 迟到也不得恢复加速。
    private var isSeeking = false
    /// 用户设置，临时速率永不覆盖该值；默认 1×。
    private(set) var userRate: Double = 1
    /// 静音开关，与 processor.isEnabled 的音量开关完全独立。
    private(set) var isEnabled = false
    /// 最近一次决策是否提交了额外速率；不是媒体时钟实测，也不等于音量增强。
    private(set) var isAccelerating = false
    /// 从基础目标切入额外速率目标的次数，不代表系统已按该倍率渲染。
    private(set) var accelerationCount = 0

    /// 注册生命周期观察，不在初始化时启动播放或定时器。
    init(player: AudioPlayerable) {
        self.player = player
        super.init()
        player.add(delegate: self)
    }

    deinit {
        timer?.invalidate()
        player.remove(delegate: self)
    }

    /// 新资源绑定一次；仅静音开关开启时运行检测，两个开关始终复用同一个 mix。
    func bind(_ processor: AudioMixVolumeBoost) {
        stop()
        self.processor = processor
        processor.setSilenceDetection(isEnabled)
        accelerationCount = 0
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 关闭立即恢复基础倍速；不启动播放、不 seek，也不修改音量。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        processor?.setSilenceDetection(enabled)
        refresh()
    }

    /// 用户倍速只接受 0.5～2；静音的临时倍率独立选择，不反写用户设置。
    func setUserRate(_ rate: Double) {
        guard rate.isFinite, (0.5...2).contains(rate) else { return }
        userRate = rate
        refresh()
    }

    /// 停止观测并恢复基础倍速；不清除用户偏好，重新播放仍使用原设置。
    func stop() {
        timer?.invalidate()
        timer = nil
        processor?.setSilenceDetection(false)
        processor = nil
        isSeeking = false
        apply(accelerating: false)
    }

    /// 只使用当前位置附近的最新连续静音观测；暂停、等待数据或观测过期时恢复。
    func refresh() {
        processor?.collectSilenceWindows()
        var permitted = false
        if case .playing = player.state, player.control == .playing, player.loading == .ended,
           !isSeeking, isEnabled, let processor = processor,
           AudioMixSilenceRatePolicy.target(userRate: userRate, capacity: (player as? AVAudioPlaybackMonitoring)?.playbackCapacity, continuing: isAccelerating) > userRate {
            permitted = processor.isSupported && processor.silenceTimeline.canAccelerate(at: player.current, continuingAfter: isAccelerating ? acceleratingSoundGeneration : nil, continuingIn: isAccelerating ? acceleratingContinuityGeneration : nil)
            // 只保护自己触发的处理链重配置；暂停、缓冲和 seek 仍立即撤销，明确有声也不等待。
            if !permitted, isAccelerating, let deadline = rateTransitionDeadline,
               ProcessInfo.processInfo.systemUptime <= deadline,
               acceleratingSoundGeneration == processor.silenceTimeline.soundGeneration,
               !processor.silenceTimeline.hasNonQuietObservation {
                permitted = true
            }
        }
        apply(accelerating: permitted)
    }

    /// 只在目标变化时设置 rate；AudioPlayer 的暂停意图仍由原后端保护。
    private func apply(accelerating: Bool) {
        let target = accelerating ? AudioMixSilenceRatePolicy.target(userRate: userRate, capacity: (player as? AVAudioPlaybackMonitoring)?.playbackCapacity, continuing: isAccelerating) : userRate
        let active = accelerating && target > userRate
        if active && !isAccelerating { accelerationCount += 1 }
        isAccelerating = active
        let changed = abs(player.rate - target) > 0.001
        if !active {
            rateTransitionDeadline = nil
            acceleratingSoundGeneration = nil
            acceleratingContinuityGeneration = nil
        } else {
            acceleratingSoundGeneration = processor?.silenceTimeline.soundGeneration
            acceleratingContinuityGeneration = processor?.silenceTimeline.continuityGeneration
            if changed { rateTransitionDeadline = ProcessInfo.processInfo.systemUptime + 0.25 }
        }
        if changed { player.rate = target }
    }

    /// 资源失败、结束或停止后不保留临时速率；重新绑定由页面负责。
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .stopped, .failed, .finished: stop()
        default: refresh()
        }
    }

    /// 暂停与缓冲通知立即撤销加速，无需等待下一次 40ms 轮询。
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) { refresh() }
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) { refresh() }

    /// seek 开始和结束均清理旧窗口；seek 中的临时目标不能被当作实际播放位置。
    func audioPlayer(_ player: AudioPlayerable, seekBegan: AudioPlayer.Seek) {
        isSeeking = true
        processor?.resetSilenceDetection()
        apply(accelerating: false)
    }
    func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek) {
        processor?.resetSilenceDetection()
        isSeeking = false
        refresh()
    }
}

/// 可重复的无版权测试信号；仅用于验证静音检测，不代表自然语音效果已经评测。
enum AudioMixSilenceSample {
    /// 14 秒双声道 WAV：0～2、6～8、12～14 秒有声，其余为静音；右声道可单独发声；quietAmplitude 供测试验证增强前检测。
    static func make(rightChannelOnly: Bool = false, quietAmplitude: Float = 0) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence-example-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 14 * 44100)!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            let time = Double(frame) / 44100
            let audible = time < 2 || (time >= 6 && time < 8) || time >= 12
            let value = Float(sin(time * 440 * 2 * .pi)) * (audible ? 0.04 : quietAmplitude)
            buffer.floatChannelData![0][frame] = rightChannelOnly ? 0 : value
            buffer.floatChannelData![1][frame] = value
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
