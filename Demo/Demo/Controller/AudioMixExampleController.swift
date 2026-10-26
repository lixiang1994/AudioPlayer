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
    private let sourceURL: URL?
    /// 音轨加载任务，不跨 await 强持有页面，停止或离开时取消。
    private var preparation: Task<Void, Never>?
    /// 使取消前的异步结果失效，不能在停止后迟到起播。
    private var generation: UInt64 = 0
    /// 当前案例；默认增强示例与既有测试入口保持一致。
    private(set) var example: Example = .boost
    /// 同一 asset 的已加载音轨，供动态构建参数使用，停止时清空。
    private var tracks: [AVAssetTrack] = []
    /// 案例选择只更新 mix，不重新准备资源；增强开关只在增强案例有效。
    private let exampleControl = UISegmentedControl(items: ["增强", "无 mix", "25%", "淡入", "淡出/恢复"])
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
        super.init(nibName: nil, bundle: nil)
    }

    /// 保留 UIKit 初始化约定，页面通常由列表纯代码创建。
    required init?(coder: NSCoder) {
        sourceURL = Bundle.main.url(forResource: "夜曲-周杰伦", withExtension: "wav")
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
        stack.spacing = 20
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
        let explanation = UILabel()
        explanation.numberOfLines = 0
        explanation.text = "默认播放 App 内置本地 WAV《夜曲》，无需网络。可在播放或暂停时切换 mix 案例，进度保持不变；淡入/淡出从选择时的媒体位置开始。2× 指 PCM 振幅增益，不代表听感响度翻倍。"
        stack.addArrangedSubview(explanation)
        exampleControl.selectedSegmentIndex = 0
        exampleControl.accessibilityIdentifier = "mix.example"
        exampleControl.addTarget(self, action: #selector(exampleChanged), for: .valueChanged)
        exampleLabel.numberOfLines = 0
        exampleLabel.font = .preferredFont(forTextStyle: .footnote)
        stack.addArrangedSubview(exampleControl)
        stack.addArrangedSubview(exampleLabel)
        updateExampleDescription()
        boostControl.selectedSegmentIndex = 0
        boostControl.accessibilityIdentifier = "mix.boost"
        boostControl.addTarget(self, action: #selector(boostChanged), for: .valueChanged)
        stack.addArrangedSubview(boostControl)
        statusLabel.numberOfLines = 0
        statusLabel.text = "尚未播放"
        statusLabel.accessibilityIdentifier = "mix.status"
        processingLabel.numberOfLines = 0
        processingLabel.font = .preferredFont(forTextStyle: .footnote)
        processingLabel.text = "等待播放音频"
        stack.addArrangedSubview(statusLabel)
        timeLabel.text = "0.0 / 0.0 秒"
        stack.addArrangedSubview(timeLabel)
        stack.addArrangedSubview(processingLabel)
        slider.isEnabled = false
        slider.accessibilityIdentifier = "mix.seek"
        slider.addTarget(self, action: #selector(seek), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        stack.addArrangedSubview(slider)
        addButton("播放 / 继续", identifier: "mix.play", to: stack) { [weak self] in self?.play() }
        addButton("暂停", identifier: "mix.pause", to: stack) { [weak self] in self?.pause() }
        addButton("停止", identifier: "mix.stop", to: stack) { [weak self] in self?.stop() }
    }

    /// 返回列表时停止独立试听，避免离开后仍有第二路声音。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    deinit {
        preparation?.cancel()
        player.remove(delegate: self)
        player.stop()
    }

    /// 有资源时只恢复播放；没有资源时异步加载一次，并安装始终存在的旁路/增强 tap。
    func play() {
        guard preparation == nil else { return }
        if player.resource != nil { player.play(); return }
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

    /// 实时切换仅更新已安装 tap 的原子目标，不替换 AVPlayerItem 或 AVAudioMix。
    func setBoostEnabled(_ enabled: Bool) {
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
        player.stop()
        boost = nil
        tracks = []
        updateProcessingStatus()
    }

    /// 案例切换只提交当前 asset 的 mix；暂停时包络也随媒体时间保持暂停。
    func selectExample(_ example: Example) {
        self.example = example
        exampleControl.selectedSegmentIndex = Example.allCases.firstIndex(of: example) ?? 0
        boostControl.isEnabled = example == .boost
        updateExampleDescription()
        if let resource = player.resource as? AVAudioPlayerResource {
            (player as? AVAudioMixControlling)?.update(audioMix: makeMix(at: player.current), for: resource.asset)
        }
        updateProcessingStatus()
    }

    /// 构建同一音轨的音量包络；此方法不启动播放、不改变进度。
    private func makeMix(at time: TimeInterval) -> AVAudioMix? {
        if example == .original { return nil }
        if example == .boost { return boost?.mix }
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
        case .boost: exampleLabel.text = "PCM 增强：原音 / 2× 共用同一个 tap，开关只更新增益。"
        case .original: exampleLabel.text = "无 mix：移除音轨处理，使用系统原音播放。"
        case .quiet: exampleLabel.text = "固定音量：所有音轨设为 25%，不改变 player.volume。"
        case .fadeIn: exampleLabel.text = "淡入：从选择位置起，5 秒媒体时间内由静音渐变到原音。"
        case .duck: exampleLabel.text = "淡出/恢复：2 秒降到静音，再用 2 秒恢复；seek 会跳到包络相应位置。"
        }
    }

    /// 选择新的包络时从当前媒体时间计算，不跳到曲目开头。
    @objc private func exampleChanged() {
        selectExample(Example.allCases[exampleControl.selectedSegmentIndex])
    }

    /// 独立案例覆盖 nil、固定音量、时间包络与 tap；排列与选择器一致。
    enum Example: CaseIterable {
        case boost, original, quiet, fadeIn, duck
    }

    /// 增强选择与播放按钮独立，未播放时切换只改变下次播放的偏好。
    @objc private func boostChanged() { setBoostEnabled(boostControl.selectedSegmentIndex == 1) }

    /// 只有进度控件主动提交寻时，增强开关不调用此方法。
    @objc private func seek() { player.seek(to: .init(time: Double(slider.value))) }

    /// 使用主线程进度回调刷新观测，实时音频线程从不直接访问 UI。
    private func updateProcessingStatus() {
        guard example == .boost else {
            processingLabel.text = "当前为音轨混合案例，不运行增强 tap；切换保持同一播放资源"
            return
        }
        guard let boost = boost else { processingLabel.text = "等待播放音频"; return }
        if boost.hasPreparedFormat && !boost.isSupported {
            processingLabel.text = "当前 PCM 格式不支持增强，音频保持原样"
            return
        }
        if boost.processedFrames == 0 { processingLabel.text = "等待 PCM 处理；目标 \(isBoostEnabled ? "2×" : "1×")"; return }
        processingLabel.text = "目标 \(isBoostEnabled ? "2×" : "1×") · 已处理 \(boost.processedFrames) 帧\n切换沿用同一个 mix 和 tap，当前格式\(boost.isSupported ? "支持" : "未支持或重新准备中")"
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
    }

    /// 更新可寻时范围；停止时禁用控件。
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        slider.maximumValue = Float(max(0, time))
        slider.isEnabled = time > 0 && player.resource != nil
    }

    /// 实际媒体进度可用于目视确认增强切换前后持续推进。
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        if !slider.isTracking { slider.value = Float(time) }
        timeLabel.text = String(format: "%.1f / %.1f 秒", time, player.duration)
        updateProcessingStatus()
    }
}
