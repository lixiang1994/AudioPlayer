#if DEBUG
import UIKit
import AVFoundation
import AudioPlayer

/// 仅由指定启动参数启用的真机诊断入口，使用原有 Manager、播放器页面和远程控制。
/// 不替换播放实现；额外状态仅供 UI 测试读取真实进度与后台时间差。
final class PlaybackDeviceDiagnostics: NSObject {
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
    init(window: UIWindow) {
        super.init()
        let manager = AudioPlayerManager.shared
        let url = Bundle.main.url(forResource: "tone", withExtension: "mp3", subdirectory: "Fixtures")!
        var first = AudioPlayerItem(id: "device-fixture-first", title: "真机测试第一集", cover: "", author: "自动验证", duration: 180, resource: url)
        var second = AudioPlayerItem(id: "device-fixture-second", title: "真机测试第二集", cover: "", author: "自动验证", duration: 180, resource: url)
        // 独立测试键每次清空，不影响手工 Demo 歌曲的播放记录。
        first.state = nil
        second.state = nil
        let controller = AudioPlayerController.instance()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.container.playButton.accessibilityIdentifier = "playback.toggle"
        controller.container.nextButton.accessibilityIdentifier = "playback.next"
        controller.container.prevButton.accessibilityIdentifier = "playback.previous"
        controller.container.slider.accessibilityIdentifier = "playback.seek"
        controller.container.titleLabel.accessibilityIdentifier = "playback.title"
        manager.player.allowedBackgroundPlayback = ProcessInfo.processInfo.environment["PLAYBACK_ALLOW_BACKGROUND"] != "0"
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
            self?.backgroundStart = manager.player.current
            self?.backgroundCount += 1
            self?.refresh()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, let start = self.backgroundStart else { return }
            self.backgroundDelta = manager.player.current - start
            self.foregroundCount += 1
            self.refresh()
        })
        manager.play(first, for: .init([first, second]))
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// 标签不写入播放器状态，时间来自库的实际读取值；暂停时也继续刷新以检查误播放。
    private func refresh() {
        let player = AudioPlayerManager.shared.player
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
            "allowedBackgroundPlayback": player.allowedBackgroundPlayback
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
