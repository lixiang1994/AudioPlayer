import UIKit
import AVFoundation
import AudioPlayer

/// 展示音量包络、动态替换及 PCM 增强；所有案例切换保留当前播放资源与控制状态。
final class AudioMixExampleController: UIViewController {
    /// 独立试听实例，不接管主列表的队列、播放记录和锁屏信息。
    let player = AudioPlayer.av.instance()
    /// 当前 item 的增强处理器；生命周期与当前资源一起清理。
    private(set) var boost: AudioMixVolumeBoost?
    /// 停止后保留用户选择，下次播放继续使用此设置。
    private(set) var isBoostEnabled = false
    /// 默认使用内置歌曲；测试可注入低振幅音频，避免以扬声器听感代替 PCM 验证。
    private var sourceURL: URL?
    /// 进入页面时的资源，切到合成样本后可返回，外部注入的网络资源也保留。
    private var originalURL: URL?
    /// 仅页面生成的临时样本由页面删除，不删除外部注入资源。
    private var sampleURL: URL?
    /// 静音加速偏好与音量增强独立保存；实时处理模式下均可启用。
    private(set) var isSilenceAccelerationEnabled = false
    /// 独立页面持有仲裁器，不影响 Manager 的用户倍速或远程命令。
    private(set) lazy var silenceAcceleration = AudioMixSilenceAcceleration(player: player)
    /// 独立静音开关；关闭它不改变 boost 的目标增益。
    private let silenceSwitch = UISwitch()
    /// 用户倍速单独选择，临时速率不写回该控件。
    private let rateControl = UISegmentedControl(items: ["用户 1×", "1.5×", "2×"])
    /// 资源来源及测试音频分段，避免把本地样本误认为 HTTP 测试。
    private let sourceLabel = UILabel()
    /// 音轨加载任务，不跨 await 强持有页面，停止或离开时取消。
    private var preparation: Task<Void, Never>?
    /// 使取消前的异步结果失效，不能在停止后迟到起播。
    private var generation: UInt64 = 0
    /// 当前案例；默认增强示例与既有测试入口保持一致。
    private(set) var example: Example = .boost
    /// 同一 asset 的已加载音轨，供动态构建参数使用，停止时清空。
    private var tracks: [AVAssetTrack] = []
    /// 实时处理合并增强与静音，另四项用于对比音轨包络；兼容既有静音测试入口。
    private let visibleExamples: [Example] = [.boost, .original, .quiet, .fadeIn, .duck]
    private let exampleControl = UISegmentedControl(items: ["实时处理", "无 mix", "25%", "淡入", "淡出"])
    /// 描述当前案例的媒体时间语义及资源来源。
    private let exampleLabel = UILabel()
    /// 原音/增强选择器；加载中、播放中、暂停时均可改变目标。
    private let boostControl = UISegmentedControl(items: ["原始音量 1×", "音量增强 2×"])
    /// 实际播放、加载、错误及处理状态说明。
    private let statusLabel = UILabel()
    /// 当前媒体时间，便于观察切换后是否连续。
    private let timeLabel = UILabel()
    /// PCM 处理观测，不声称等于扬声器声压或主观响度。
    private let processingLabel = UILabel()
    /// 进度拖动只提交最终位置；增强切换不触发 seek。
    private let slider = UISlider()

    /// 默认资源已随 Demo 打包，无需外网；nil 用于验证缺失资源提示。
    init(url: URL? = Bundle.main.url(forResource: "夜曲-周杰伦", withExtension: "wav")) {
        sourceURL = url
        originalURL = url
        super.init(nibName: nil, bundle: nil)
    }

    /// 保留 UIKit 初始化约定，页面通常由列表纯代码创建。
    required init?(coder: NSCoder) {
        sourceURL = Bundle.main.url(forResource: "夜曲-周杰伦", withExtension: "wav")
        originalURL = sourceURL
        super.init(coder: coder)
    }

    /// 创建试听控件并订阅状态，打开页面不自动开始播放。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AudioMix 案例"
        view.backgroundColor = .systemBackground
        player.add(delegate: self)
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        addHeading("1 · 选择试听资源", to: stack)
        sourceLabel.numberOfLines = 0
        sourceLabel.font = .preferredFont(forTextStyle: .footnote)
        sourceLabel.accessibilityIdentifier = "mix.source"
        updateSourceDescription()
        stack.addArrangedSubview(sourceLabel)
        let sources = UIStackView()
        sources.axis = .horizontal
        sources.distribution = .fillEqually
        sources.spacing = 12
        addButton("原音频", identifier: "mix.source.original", to: sources) { [weak self] in self?.loadOriginalSource() }
        addButton("声音 / 静音样本", identifier: "mix.silence.sample", to: sources) { [weak self] in self?.loadSilenceSample() }
        stack.addArrangedSubview(sources)

        addHeading("2 · 播放与进度", to: stack)
        statusLabel.numberOfLines = 0
        statusLabel.text = "尚未播放"
        statusLabel.accessibilityIdentifier = "mix.status"
        stack.addArrangedSubview(statusLabel)
        timeLabel.text = "0.0 / 0.0 秒"
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        stack.addArrangedSubview(timeLabel)
        slider.isEnabled = false
        slider.accessibilityIdentifier = "mix.seek"
        slider.addTarget(self, action: #selector(seek), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        stack.addArrangedSubview(slider)
        let playback = UIStackView()
        playback.distribution = .fillEqually
        addButton("播放 / 继续", identifier: "mix.play", to: playback) { [weak self] in self?.play() }
        addButton("暂停", identifier: "mix.pause", to: playback) { [weak self] in self?.pause() }
        addButton("停止", identifier: "mix.stop", to: playback) { [weak self] in self?.stop() }
        stack.addArrangedSubview(playback)
        processingLabel.numberOfLines = 0
        processingLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        processingLabel.accessibilityIdentifier = "mix.processing"
        processingLabel.text = "等待播放音频"

        addHeading("3 · 切换效果，比较听感", to: stack)
        exampleControl.selectedSegmentIndex = 0
        exampleControl.accessibilityIdentifier = "mix.example"
        exampleControl.addTarget(self, action: #selector(exampleChanged), for: .valueChanged)
        stack.addArrangedSubview(exampleControl)
        exampleLabel.numberOfLines = 0
        exampleLabel.font = .preferredFont(forTextStyle: .footnote)
        stack.addArrangedSubview(exampleLabel)
        updateExampleDescription()
        boostControl.selectedSegmentIndex = 0
        boostControl.accessibilityIdentifier = "mix.boost"
        boostControl.addTarget(self, action: #selector(boostChanged), for: .valueChanged)
        stack.addArrangedSubview(boostControl)
        let silenceTitle = UILabel()
        silenceTitle.text = "静音加速 · 目标 3×"
        silenceSwitch.accessibilityIdentifier = "mix.silence"
        silenceSwitch.accessibilityLabel = "静音加速"
        silenceSwitch.addTarget(self, action: #selector(silenceChanged), for: .valueChanged)
        let silenceRow = UIStackView(arrangedSubviews: [silenceTitle, silenceSwitch])
        silenceRow.spacing = 8
        silenceRow.alignment = .center
        stack.addArrangedSubview(silenceRow)
        rateControl.selectedSegmentIndex = 0
        rateControl.accessibilityIdentifier = "mix.userRate"
        rateControl.addTarget(self, action: #selector(userRateChanged), for: .valueChanged)
        stack.addArrangedSubview(rateControl)
        stack.addArrangedSubview(processingLabel)
        let comparisons = UIStackView()
        comparisons.distribution = .fillEqually
        addButton("再次应用效果", identifier: "mix.reapply", to: comparisons) { [weak self] in
            guard let self = self else { return }
            self.selectExample(self.example)
        }
        addButton("跳至静音段", identifier: "mix.silence.seek", to: comparisons) { [weak self] in self?.seekToSilenceSample() }
        stack.addArrangedSubview(comparisons)

    }

    /// 返回列表时停止独立试听，避免离开后仍有第二路声音。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    deinit {
        preparation?.cancel()
        silenceAcceleration.stop()
        if let url = sampleURL { try? FileManager.default.removeItem(at: url) }
        player.remove(delegate: self)
        player.stop()
    }

    /// 有资源时只恢复播放；没有资源时异步加载一次，并安装始终存在的旁路/增强 tap。
    func play() {
        guard preparation == nil else { return }
        // 独立页面可能在列表尚未播放时打开，不能依赖 Manager 之前激活过全局会话。
        // 使用宿主既有的 playback 策略以支持后台；离开时仅停止自己的播放器，不停用全局会话。
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            statusLabel.text = "音频会话激活失败：\(error.localizedDescription)"
            return
        }
        if player.resource != nil {
            // finished 后驱动器已停止；重播仍需重新绑定并清理上一轮时间线。
            if case .finished = player.state, let boost = boost { silenceAcceleration.bind(boost) }
            player.play()
            return
        }
        guard let url = sourceURL else { statusLabel.text = "内置试听音频缺失"; return }
        statusLabel.text = "正在准备"
        let generation = self.generation
        preparation = Task { [weak self] in
            do {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard !Task.isCancelled, let self = self, self.generation == generation else { return }
                let boost = try AudioMixVolumeBoost(tracks: tracks)
                // 读取加载完成时的最新选择，加载期间反复切换不会提交过期增益。
                boost.setEnabled(self.isBoostEnabled)
                self.boost = boost
                self.silenceAcceleration.bind(boost)
                self.silenceAcceleration.setEnabled(self.usesProcessingTap && self.isSilenceAccelerationEnabled)
                self.preparation = nil
                self.tracks = tracks
                // 加载中切换案例以最新选择为准，首次播放的包络从零开始。
                self.player.prepare(resource: AVAudioPlayerResource(asset: asset, audioMix: self.makeMix(at: 0)))
            } catch {
                guard !Task.isCancelled, let self = self, self.generation == generation else { return }
                self.preparation = nil
                self.statusLabel.text = "准备失败：\(error.localizedDescription)"
            }
        }
    }

    /// 实时模式仅更新 tap 的原子目标；包络对比中操作时先恢复 tap，不替换 item。
    func setBoostEnabled(_ enabled: Bool) {
        if !usesProcessingTap { selectExample(.boost) }
        isBoostEnabled = enabled
        boostControl.selectedSegmentIndex = enabled ? 1 : 0
        boost?.setEnabled(enabled)
        updateProcessingStatus()
    }

    /// 准备中暂停会取消加载，避免异步完成后突然起播；已播放资源正常暂停。
    func pause() {
        if preparation != nil { stop() } else { player.pause() }
    }

    /// 先取消旧任务，再清理 item 和 tap；已提交的处理状态由系统最终释放。
    func stop() {
        generation &+= 1
        preparation?.cancel()
        preparation = nil
        silenceAcceleration.stop()
        player.stop()
        boost = nil
        tracks = []
        updateProcessingStatus()
    }

    /// 案例切换只提交当前 asset 的 mix；暂停时包络也随媒体时间保持暂停。
    func selectExample(_ example: Example) {
        let previous = self.example
        self.example = example
        exampleControl.selectedSegmentIndex = visibleExamples.firstIndex(of: example == .silence ? .boost : example) ?? 0
        silenceAcceleration.setEnabled(usesProcessingTap && isSilenceAccelerationEnabled)
        updateExampleDescription()
        let sameTap = (previous == .boost || previous == .silence) && (example == .boost || example == .silence)
        if !sameTap, let resource = player.resource as? AVAudioPlayerResource {
            (player as? AVAudioMixControlling)?.update(audioMix: makeMix(at: player.current), for: resource.asset)
        }
        updateProcessingStatus()
    }

    /// 构建同一音轨的音量包络；此方法不启动播放、不改变进度。
    private func makeMix(at time: TimeInterval) -> AVAudioMix? {
        if example == .original { return nil }
        if example == .boost || example == .silence { return boost?.mix }
        let start = CMTime(seconds: max(0, time), preferredTimescale: 600)
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            switch example {
            case .quiet:
                parameters.setVolume(0.25, at: .zero)
            case .fadeIn:
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: start, duration: CMTime(seconds: 5, preferredTimescale: 600)))
            case .duck:
                let duration = CMTime(seconds: 2, preferredTimescale: 600)
                parameters.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: start, duration: duration))
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: start + duration, duration: duration))
            default: break
            }
            return parameters
        }
        return mix
    }

    /// 每个案例的效果与时间单位由页面直接说明，避免把淡入当作重新播放。
    private func updateExampleDescription() {
        switch example {
        case .boost, .silence: exampleLabel.text = "增强与静音加速独立开关，播放中切换保留进度。3× 不支持时回退 2×，有声或缓冲不足恢复用户倍速。音乐伴奏通常不会触发静音；建议用声音 / 静音样本观察。2× 增强指振幅约 +6dB，不是听感响度翻倍。"
        case .original: exampleLabel.text = "对比基线：移除 mix，使用系统原音；增强与静音偏好保留但暂不生效。操作功能开关会返回实时处理，播放位置不变。"
        case .quiet: exampleLabel.text = "固定音量：所有音轨设为 25%，不改变播放位置。增强与静音暂不生效，操作功能开关返回实时处理。"
        case .fadeIn: exampleLabel.text = "淡入：从选择位置起，5 秒媒体时间内由静音渐变到原音；点击再次应用效果可在当前位置再试一次。"
        case .duck: exampleLabel.text = "淡出/恢复：2 秒降到静音，再用 2 秒恢复；点击再次应用效果可在当前位置再试一次。"
        }
    }

    /// 选择新的包络时从当前媒体时间计算，不跳到曲目开头。
    @objc private func exampleChanged() {
        selectExample(visibleExamples[exampleControl.selectedSegmentIndex])
    }

    /// 独立案例覆盖 nil、固定音量、时间包络与 tap；silence 为既有诊断入口的别名。
    enum Example: CaseIterable {
        case boost, original, quiet, fadeIn, duck, silence
    }

    /// 静音开关不修改音量目标；包络对比中操作时先返回 tap 模式，保持播放位置与意图。
    func setSilenceAccelerationEnabled(_ enabled: Bool) {
        if !usesProcessingTap { selectExample(.boost) }
        isSilenceAccelerationEnabled = enabled
        silenceSwitch.isOn = enabled
        silenceAcceleration.setEnabled(usesProcessingTap && enabled)
        updateProcessingStatus()
    }

    /// 基础倍速供用户独立选择；仲裁器根据当前检测结果提交目标速率。
    func setUserRate(_ rate: Double) {
        silenceAcceleration.setUserRate(rate)
        rateControl.selectedSegmentIndex = [1.0, 1.5, 2.0].firstIndex(of: silenceAcceleration.userRate) ?? UISegmentedControl.noSegment
        updateProcessingStatus()
    }

    /// 合成样本仅替换试听资源；生成在工作线程，取消或页面销毁后删除迟到文件。
    func loadSilenceSample() {
        stop()
        selectExample(.boost)
        // 专用样本主动开启静音，加载期间的再次操作仍以用户最新偏好为准；不改变音量增强。
        setSilenceAccelerationEnabled(true)
        statusLabel.text = "正在生成测试音频"
        let generation = self.generation
        preparation = Task { [weak self] in
            do {
                let url = try await Task.detached(priority: .userInitiated) { try AudioMixSilenceSample.make() }.value
                guard !Task.isCancelled, let self = self, self.generation == generation else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                if let old = self.sampleURL { try? FileManager.default.removeItem(at: old) }
                self.sampleURL = url
                self.sourceURL = url
                self.updateSourceDescription()
                self.preparation = nil
                self.play()
            } catch {
                guard !Task.isCancelled, let self = self, self.generation == generation else { return }
                self.preparation = nil
                self.statusLabel.text = "样本生成失败：\(error.localizedDescription)"
            }
        }
    }

    /// 两个 UI 事件只修改各自偏好，不互相开启或关闭。
    @objc private func silenceChanged() { setSilenceAccelerationEnabled(silenceSwitch.isOn) }
    /// 用户选择与当前临时速率分开，避免从 1× 加速后 UI 错误显示为 3× 设置。
    @objc private func userRateChanged() { setUserRate([1.0, 1.5, 2.0][rateControl.selectedSegmentIndex]) }

    /// 增强选择与播放按钮独立，未播放时切换只改变下次播放的偏好。
    @objc private func boostChanged() { setBoostEnabled(boostControl.selectedSegmentIndex == 1) }

    /// 只有进度控件主动提交寻时，增强开关不调用此方法。
    @objc private func seek() { player.seek(to: .init(time: Double(slider.value))) }

    /// 使用主线程进度回调刷新观测，实时音频线程从不直接访问 UI。
    private func updateProcessingStatus() {
        processingLabel.textColor = .label
        guard usesProcessingTap else {
            processingLabel.text = String(format: "用户 %.1f× / 当前目标 %.1f× · %@\n包络音量目标 %.0f%% · 增强与静音暂不生效\n操作功能开关返回实时处理，播放位置保持不变", silenceAcceleration.userRate, player.rate, playbackStatus, envelopeVolume * 100)
            return
        }
        guard let boost = boost else { processingLabel.text = "等待播放音频"; return }
        if boost.hasPreparedFormat && !boost.isSupported {
            processingLabel.text = "当前 PCM 格式不支持增强，音频保持原样"
            return
        }
        if boost.processedFrames == 0 { processingLabel.text = "等待 PCM 处理；目标 \(isBoostEnabled ? "2×" : "1×")"; return }
        let acceleration = silenceAcceleration
        let gain = boost.measuredGain.map { String(format: "%.2f×", $0) } ?? "当前块静音，无有效比值"
        let capacity = (player as? AVAudioPlaybackMonitoring)?.playbackCapacity
        let target = capacity.map { $0.canPlayFastForward ? "3×" : "2×（媒体能力回退）" } ?? "等待媒体就绪"
        let detection: String
        if !isSilenceAccelerationEnabled { detection = "关闭" }
        else if player.control != .playing { detection = "暂停，保持用户倍速" }
        else if player.loading != .ended { detection = "缓冲中，保持用户倍速" }
        else if acceleration.isAccelerating { detection = "静音段加速中" }
        else if AudioMixSilenceRatePolicy.target(userRate: acceleration.userRate, capacity: capacity, continuing: false) <= acceleration.userRate {
            detection = "媒体能力 / 缓冲限制，保持用户倍速"
        } else { detection = "等待连续静音（伴奏、轻声也可能有声）" }
        processingLabel.text = String(format: "用户 %.1f× → 当前目标 %.1f× · %@ · 静音目标 %@\n静音：%@ · 已触发 %d 次\n音量目标 %@ · PCM 峰值比 %@\n已处理 %llu 帧", acceleration.userRate, player.rate, playbackStatus, target, detection, acceleration.accelerationCount, isBoostEnabled ? "2×" : "1×", gain, boost.processedFrames)
        processingLabel.textColor = acceleration.isAccelerating ? .systemGreen : .label
    }

    /// rate 仅代表控制目标；状态来自后端反馈，不能用目标倍率冒充媒体时钟实测。
    private var playbackStatus: String {
        switch player.state {
        case .stopped: return "已停止"
        case .prepare: return "准备中"
        case .finished: return "已结束"
        case .failed: return "播放失败"
        case .playing:
            if player.loading != .ended { return "缓冲中" }
            return player.control == .playing ? "播放中" : "已暂停"
        }
    }

    /// 按当前媒体时间插值展示已提交的包络目标，便于观察 25% 与渐变；不冒充扬声器实测音量。
    private var envelopeVolume: Float {
        guard let parameters = (player as? AVAudioMixControlling)?.audioMix?.inputParameters.first else { return 1 }
        var start: Float = 1
        var end: Float = 1
        var range = CMTimeRange.zero
        let time = player.current
        guard parameters.getVolumeRamp(for: CMTime(seconds: time, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range) else { return 1 }
        let duration = range.duration.seconds
        guard duration.isFinite, duration > 0 else { return start }
        let fraction = Float(min(1, max(0, (time - range.start.seconds) / duration)))
        return start + (end - start) * fraction
    }

    /// 增强和静音共用实时处理模式；旧静音案例仅保留内部测试与诊断兼容。
    private var usesProcessingTap: Bool { example == .boost || example == .silence }

    /// 明确标出当前资源与适合观察的效果，避免把本地样本当成网络验证。
    private func updateSourceDescription() {
        if sourceURL == sampleURL, sampleURL != nil {
            sourceLabel.text = "本地合成 WAV · 14 秒\n有声 0～2 / 6～8 / 12～14 秒；静音 2～6 / 8～12 秒。用于观察倍率变化，不代表自然语音效果。"
        } else {
            sourceLabel.text = (sourceURL?.isFileURL == false ? "网络音频 · " : "本地音频 · ") + (sourceURL?.lastPathComponent ?? "资源缺失") + "\n适合比较音量、25% 与渐变；持续伴奏通常不会触发静音加速。切换资源会从头播放。"
        }
    }

    /// 返回最初资源时取消未完成的样本生成；保留效果、双开关与用户倍速偏好。
    func loadOriginalSource() {
        stop()
        sourceURL = originalURL
        updateSourceDescription()
        play()
    }

    /// 仅合成样本有已知静音位置；普通音乐不能猜测静音位置或隐式换成测试音频。
    func seekToSilenceSample() {
        guard let sampleURL = sampleURL, sourceURL == sampleURL, player.resource != nil else {
            statusLabel.text = "请先加载声音 / 静音样本，再跳至静音段"
            return
        }
        player.seek(to: .init(time: 2.1))
    }

    /// 分区标题将资源切换、播放控制和效果选择明确分开，小屏可滚动。
    private func addHeading(_ text: String, to stack: UIStackView) {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(label)
    }

    /// 保留自动化标识与足够点击高度，小屏可滚动操作。
    private func addButton(_ title: String, identifier: String, to stack: UIStackView, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
}

extension AudioMixExampleController: AudioPlayerDelegate {
    /// 资源状态与控制状态分开；播放失败时解除页面持有的处理器。
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .prepare: statusLabel.text = "准备中"
        case .playing: statusLabel.text = player.control == .playing ? "播放中" : "已就绪 / 暂停"
        case .stopped: statusLabel.text = "已停止"
        case .finished: statusLabel.text = "已结束，可再次播放"
        case .failed(let error):
            boost = nil
            statusLabel.text = "播放失败：\(error?.localizedDescription ?? "未知错误")"
        }
        slider.isEnabled = player.duration > 0 && player.resource != nil
        updateProcessingStatus()
    }

    /// 切换增强不产生控制事件，只有实际播放/暂停变化才修改此状态。
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        statusLabel.text = state == .playing ? "播放中" : "已暂停"
        updateProcessingStatus()
    }

    /// 更新可寻时范围；停止时禁用控件。
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        slider.maximumValue = Float(max(0, time))
        slider.isEnabled = time > 0 && player.resource != nil
    }

    /// 实际媒体进度可用于目视确认增强切换前后持续推进。
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        if !slider.isTracking { slider.value = Float(time) }
        let sample = sourceURL == sampleURL && sampleURL != nil
        let quiet = (2..<6).contains(time) || (8..<12).contains(time)
        timeLabel.text = String(format: "%.1f / %.1f 秒", time, player.duration) + (sample ? (quiet ? " · 静音段" : " · 有声段") : "")
        updateProcessingStatus()
    }
}
