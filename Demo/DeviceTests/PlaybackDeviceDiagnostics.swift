#if DEBUG
import UIKit
import AVFoundation
import AudioPlayer

/// 仅由指定启动参数启用的真机诊断入口，使用原有 Manager 播放页或独立 AudioMix 页。
/// 不替换播放实现；额外状态仅供 UI 测试读取真实进度与后台时间差。
final class PlaybackDeviceDiagnostics: NSObject {
    /// 可选的静音试听页；只有显式测试环境变量开启时使用，沿用真实页面的 tap 与倍速仲裁。
    private var silenceController: AudioMixExampleController?
    /// 页面持有诊断器，计时器仅弱引用诊断器，避免测试结束后遗留持有环。
    private var timer: Timer?
    /// 上一次真实进入后台时的播放位置。
    private var backgroundStart: TimeInterval?
    /// 最近一次回前台时计算的实际媒体进度差。
    private var backgroundDelta: TimeInterval = 0
    /// 真实生命周期事件计数，用于区分默认零值与实际进入过后台。
    private var backgroundCount = 0
    private var foregroundCount = 0
    /// UI 测试通过此标签读取原始媒体秒数，而非只看按钮选中状态。
    private let status = UILabel()
    /// 生命周期监听令牌，销毁时逐一归还。
    private var observers: [NSObjectProtocol] = []

    /// 使用独立测试资源和记录键；缺失资源时直接暴露配置错误，不退回公网音频。
    /// silenceExample 默认读取启动环境；测试可显式传入，覆盖两种页面的返回路径。
    init(window: UIWindow, silenceExample: Bool = ProcessInfo.processInfo.environment["PLAYBACK_SILENCE"] == "1") {
        super.init()
        let manager = AudioPlayerManager.shared
        let url = Bundle.main.url(forResource: "tone", withExtension: "mp3", subdirectory: "Fixtures")!
        var first = AudioPlayerItem(id: "device-fixture-first", title: "真机测试第一集", cover: "", author: "自动验证", duration: 180, resource: url)
        var second = AudioPlayerItem(id: "device-fixture-second", title: "真机测试第二集", cover: "", author: "自动验证", duration: 180, resource: url)
        // 独立测试键每次清空，不影响手工 Demo 歌曲的播放记录。
        first.state = nil
        second.state = nil
        let controller: UIViewController
        if silenceExample {
            let url = Bundle.main.url(forResource: "silence", withExtension: "mp3", subdirectory: "Fixtures")!
            let example = AudioMixExampleController(url: url)
            silenceController = example
            controller = example
        } else {
            controller = AudioPlayerController.instance()
        }
        // 诊断页也必须保留列表作为返回目标，不能将裸页面替换成窗口根页面。
        // 正常启动复用 storyboard 的导航栈；独立测试窗口则补齐相同的列表入口。
        let navigation = window.rootViewController as? UINavigationController
            ?? UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() as! UINavigationController
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(controller, animated: false)
        controller.loadViewIfNeeded()
        if let controller = controller as? AudioPlayerController {
            controller.container.playButton.accessibilityIdentifier = "playback.toggle"
            controller.container.nextButton.accessibilityIdentifier = "playback.next"
            controller.container.prevButton.accessibilityIdentifier = "playback.previous"
            controller.container.slider.accessibilityIdentifier = "playback.seek"
            controller.container.titleLabel.accessibilityIdentifier = "playback.title"
        }
        let player = silenceController?.player ?? manager.player
        player.allowedBackgroundPlayback = ProcessInfo.processInfo.environment["PLAYBACK_ALLOW_BACKGROUND"] != "0"
        status.accessibilityIdentifier = "playback.diagnostics"
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .white
        status.backgroundColor = .black
        status.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(status)
        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            status.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)
        ])
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.backgroundStart = player.current
            self?.backgroundCount += 1
            self?.refresh()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, let start = self.backgroundStart else { return }
            self.backgroundDelta = player.current - start
            self.foregroundCount += 1
            self.refresh()
        })
        if let controller = silenceController {
            controller.selectExample(.silence)
            controller.setSilenceAccelerationEnabled(true)
            controller.setBoostEnabled(true)
            controller.play()
        } else {
            manager.play(first, for: .init([first, second]))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// 标签不写入播放器状态，时间来自库的实际读取值；暂停时也继续刷新以检查误播放。
    private func refresh() {
        let player = silenceController?.player ?? AudioPlayerManager.shared.player
        let control = player.control == .playing ? "playing" : "paused"
        status.text = String(format: "%@|%.2f|bg=%.2f", control, player.current, backgroundDelta)
        // 只在显式测试模式写诊断文件，供 devicectl 读取；不使用私有 API 操作系统界面。
        let record: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "current": player.current,
            "control": control,
            "backgroundDelta": backgroundDelta,
            "backgroundCount": backgroundCount,
            "foregroundCount": foregroundCount,
            "applicationState": UIApplication.shared.applicationState.rawValue,
            "allowedBackgroundPlayback": player.allowedBackgroundPlayback,
            "silenceExample": silenceController != nil,
            "rate": player.rate,
            "accelerating": silenceController?.silenceAcceleration.isAccelerating ?? false,
            "accelerationCount": silenceController?.silenceAcceleration.accelerationCount ?? 0,
            "boostedFrames": silenceController?.boost?.boostedFrames ?? 0
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("playback-device-state.json")
            try data.write(to: url, options: .atomic)
        } catch {
            status.text = "诊断文件写入失败：\(error.localizedDescription)"
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
#endif
