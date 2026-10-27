import XCTest
import UIKit
import AVFoundation
@testable import AudioPlayer
@testable import Demo

/// 验证 Demo 的队列切换、恢复播放记录和自然结束回调，与真实库模块一同运行。
final class DemoIntegrationTests: PlaybackTestCase {
    /// 独立 Manager 验证业务层，退出时清空，避免污染全局锁屏控制。
    private var manager: AudioPlayerManager!
    /// 测试使用独立记录键，结束后仅移除本测试的数据。
    private var items: [AudioPlayerItem] = []
    
    override func setUp() {
        super.setUp()
        manager = AudioPlayerManager()
        items = [makeItem(audio), makeItem(otherAudio)]
    }
    
    override func tearDown() {
        manager.clear()
        manager = nil
        for var item in items { item.state = nil }
        items = []
        super.tearDown()
    }
    
    /// 真机诊断入口必须保留列表和返回按钮，持续播放后退出也要停止 AudioMix。
    func testDeviceDiagnosticsPreservesAudioMixNavigationAndStopsOnReturn() throws {
        for existingNavigation in [false, true] {
            let window = UIWindow(frame: UIScreen.main.bounds)
            // 真机窗口必须绑定活动场景，UIKit 才会派发真实的显示和退出生命周期。
            if #available(iOS 13.0, *) {
                window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            }
            let original = existingNavigation
                ? UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() as? UINavigationController
                : nil
            window.rootViewController = original
            let diagnostics = PlaybackDeviceDiagnostics(window: window, silenceExample: true)
            defer { window.isHidden = true; window.rootViewController = nil }
            let navigation = try XCTUnwrap(window.rootViewController as? UINavigationController)
            if let original = original { XCTAssertTrue(navigation === original) }
            XCTAssertTrue(navigation.viewControllers.first is AudioPlayerListController)
            let controller = try XCTUnwrap(navigation.topViewController as? AudioMixExampleController)
            defer { controller.stop() }
            eventually("诊断页应实际播放") { controller.player.current > 0.2 }
            // 跨过多次状态刷新和静音倍速切换，检查导航栈未被异步任务替换。
            pump(8)
            XCTAssertTrue(window.rootViewController === navigation)
            XCTAssertFalse(navigation.isNavigationBarHidden)
            XCTAssertFalse(navigation.navigationBar.topItem?.hidesBackButton ?? true)
            XCTAssertEqual(navigation.viewControllers.count, 2)
            XCTAssertNotNil(navigation.navigationBar.backItem)
            navigation.popViewController(animated: false)
            pump(0.2)
            XCTAssertTrue(navigation.topViewController is AudioPlayerListController)
            XCTAssertNil(controller.player.resource, "返回列表应结束试听，不得继续后台发声")
            XCTAssertFalse(controller.silenceAcceleration.isAccelerating)
            withExtendedLifetime(diagnostics) {}
        }
    }

    /// 普通播放的诊断入口同样可返回原列表，不能为修复 AudioMix 破坏既有 UI 测试入口。
    func testDeviceDiagnosticsPreservesRegularPlayerNavigation() throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        if #available(iOS 13.0, *) {
            window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        }
        let diagnostics = PlaybackDeviceDiagnostics(window: window, silenceExample: false)
        defer {
            AudioPlayerManager.shared.clear()
            window.isHidden = true
            window.rootViewController = nil
        }
        let navigation = try XCTUnwrap(window.rootViewController as? UINavigationController)
        XCTAssertTrue(navigation.viewControllers.first is AudioPlayerListController)
        XCTAssertTrue(navigation.topViewController is AudioPlayerController)
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        navigation.popViewController(animated: false)
        XCTAssertTrue(navigation.topViewController is AudioPlayerListController)
        withExtendedLifetime(diagnostics) {}
    }

    /// 状态文案区分目标倍率和播放反馈，暂停时不能把已保存的目标说成实际播放。
    func testMixRateLabelDistinguishesTargetAndPausedState() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.setUserRate(1.5)
        controller.play()
        defer { controller.stop() }
        eventually("播放页应真正处理 PCM") { (controller.boost?.processedFrames ?? 0) > 4096 }
        controller.pause()
        for example in [AudioMixExampleController.Example.boost, .quiet] {
            controller.selectExample(example)
            let label = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.processing") as? UILabel)
            XCTAssertTrue(label.text?.contains("当前目标 1.5×") == true)
            XCTAssertTrue(label.text?.contains("已暂停") == true)
            XCTAssertFalse(label.text?.contains("实际") == true)
            let position = controller.player.current
            pump(0.2)
            XCTAssertEqual(controller.player.current, position, accuracy: 0.03)
        }
    }

    /// 使用真实底层状态及单调时钟验证静音提速，防止目标字段正确但播放器未执行。
    func testSilenceRateMatchesAVPlayerAndMediaClock() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        var tracks: [AVAssetTrack]?
        var loadError: Error?
        let task = Task {
            do { tracks = try await asset.loadTracks(withMediaType: .audio) }
            catch { loadError = error }
        }
        defer { task.cancel() }
        eventually("样本音轨应加载") { tracks != nil || loadError != nil }
        XCTAssertNil(loadError)
        let boost = try AudioMixVolumeBoost(tracks: XCTUnwrap(tracks))
        let avPlayer = AVPlayer()
        engine.stop()
        engine = AudioPlayerAVEngine(.init(), player: avPlayer)
        let driver = AudioMixSilenceAcceleration(player: engine)
        driver.bind(boost)
        driver.setEnabled(true)
        defer { driver.stop(); engine.stop() }
        engine.prepare(resource: AVAudioPlayerResource(asset: asset, audioMix: boost.mix))
        engine.play()
        eventually("等待静音中部的稳定加速") { driver.isAccelerating && self.engine.current > 2.8 && self.engine.current < 4.5 }
        let target = expectedSilenceRate(engine)
        XCTAssertEqual(avPlayer.timeControlStatus, .playing)
        XCTAssertEqual(Double(avPlayer.rate), target, accuracy: 0.01)
        let mediaStart = avPlayer.currentTime().seconds
        let clockStart = ProcessInfo.processInfo.systemUptime
        pump(0.35)
        let measured = (avPlayer.currentTime().seconds - mediaStart) / (ProcessInfo.processInfo.systemUptime - clockStart)
        let measurement = XCTAttachment(string: "local WAV: target=\(target), AVPlayer.rate=\(avPlayer.rate), media/uptime=\(measured)")
        measurement.lifetime = .keepAlways
        add(measurement)
        XCTAssertTrue(driver.isAccelerating)
        XCTAssertLessThan(avPlayer.currentTime().seconds, 6, "测量不能跨入有声区间")
        XCTAssertEqual(avPlayer.timeControlStatus, .playing)
        XCTAssertEqual(measured, target, accuracy: 0.35, "实测媒体推进必须接近能力允许的 3× 或 2×")
        engine.pause()
        driver.setUserRate(1.5)
        pump(0.1)
        XCTAssertEqual(engine.rate, 1.5)
        XCTAssertEqual(avPlayer.rate, 0)
        let paused = avPlayer.currentTime().seconds
        pump(0.25)
        XCTAssertEqual(avPlayer.currentTime().seconds, paused, accuracy: 0.01)
    }

    /// 高频读取相邻强弱块的峰值比，输入/输出必须配对；真实音频线程持续发布统计。
    func testBoostPeakPairsRemainConsistentAcrossChangingBlocks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("peak-pairs-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 6))
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            // 每 4096 帧切换 25 倍振幅，配对错误会产生远大于或小于 2 的比值。
            let amplitude = index / 4096 % 2 == 0 ? 0.01 : 0.25
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 44100) * amplitude)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("等待增益过渡结束") { (controller.boost?.boostedFrames ?? 0) > 4096 }
        let boost = try XCTUnwrap(controller.boost)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var reads = 0
        var low = false, high = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            for _ in 0..<256 {
                let gain = try XCTUnwrap(boost.measuredGain)
                XCTAssertEqual(gain, 2, accuracy: 0.002)
                reads += 1
            }
            let peak = boost.outputPeak
            low = low || peak < 0.03
            high = high || peak > 0.4
            pump(0.001)
        }
        XCTAssertGreaterThan(reads, 1000)
        XCTAssertTrue(low && high, "必须实际观察到相邻强弱块，恒定振幅不能验证配对")
    }

    /// Manager 的 prepare 后 seek 调用顺序应能恢复记录，切下一集时不得污染新记录。
    func testManagerRestoresProgressAndSwitchesQueue() {
        var item = items[0]
        item.state = .record(8)
        manager.play(item, for: .init(items))
        eventually("Demo 应从记录继续播放") { self.manager.player.current > 8 && self.manager.player.current < 10 }
        manager.playNext()
        eventually("Demo 应切到下一集") { self.manager.item?.id == self.items[1].id && self.manager.player.current > 0.05 }
        XCTAssertLessThan(manager.player.current, 2)
        manager.playPrev()
        eventually("返回上一集应恢复原进度") { self.manager.item?.id == item.id && self.manager.player.current > 8 }
    }
    
    /// 自然结束回调中同步准备下一集，是实际业务中的 delegate 重入路径。
    func testManagerAutomaticallyAdvancesAfterFinish() {
        let short = makeItem(PlaybackFixtures.shortAudio)
        items.append(short)
        manager.play(short, for: .init([short, items[0]]))
        eventually("自然结束应自动播放下一集") { self.manager.item?.id == self.items[0].id && self.manager.player.current > 0.1 }
        if case .playing = manager.player.state {} else { XCTFail("旧结束事件不应覆盖新单集状态") }
    }
    
    /// 真实 tap 回调必须输出 1 倍和 2 倍 PCM，不能只检查 UI 或目标变量。
    func testBoostTapActuallyProcessesOriginalAndDoubleGain() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        defer { controller.stop() }
        controller.play()
        eventually("原音应实际进入 tap") { (controller.boost?.processedFrames ?? 0) > 4096 }
        let boost = try XCTUnwrap(controller.boost)
        XCTAssertTrue(boost.isSupported)
        eventually("原音 PCM 峰值应保持 1 倍") { abs((boost.measuredGain ?? 0) - 1) < 0.02 }
        controller.setBoostEnabled(true)
        eventually("增强 PCM 应有稳定的 2 倍处理块") { boost.boostedFrames > 4096 && abs((boost.measuredGain ?? 0) - 2) < 0.02 }
        controller.setBoostEnabled(false)
        eventually("关闭增强应恢复原始 PCM") { abs((boost.measuredGain ?? 0) - 1) < 0.02 }
    }

    /// 强信号放大后在 PCM 合法范围限幅，不溢出成负值或产生非有限数。
    func testBoostTapLimitsClippingForLoudPCM() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boost-clipping-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132300))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for index in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData![channel][index] = Float(sin(Double(index) * 440 * 2 * .pi / 44100) * 0.75)
            }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("限幅信号必须实际经过增强处理") { (controller.boost?.boostedFrames ?? 0) > 4096 }
        let boost = try XCTUnwrap(controller.boost)
        eventually("0.75 峰值经 2 倍增强应限制为 1") { abs(boost.outputPeak - 1) < 0.001 }
        XCTAssertLessThanOrEqual(boost.outputPeak, 1)
    }

    /// 反复切换增强不创建资源、不回零、不改变暂停状态；恢复仍从同一位置继续。
    func testBoostSwitchPreservesResourceProgressAndPause() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        defer { controller.stop() }
        controller.play()
        eventually("先播放一秒") { controller.player.current > 1 }
        let resource = try XCTUnwrap(controller.player.resource as? AVAudioPlayerResource)
        let boost = try XCTUnwrap(controller.boost)
        for index in 0..<20 {
            let before = controller.player.current
            controller.setBoostEnabled(index % 2 == 0)
            XCTAssertTrue(controller.boost === boost)
            XCTAssertTrue((controller.player.resource as? AVAudioPlayerResource)?.asset === resource.asset)
            XCTAssertEqual(controller.player.current, before, accuracy: 0.1)
            XCTAssertEqual(controller.player.control, .playing)
        }
        controller.pause()
        let position = controller.player.current
        controller.setBoostEnabled(true)
        pump(0.2)
        controller.setBoostEnabled(false)
        XCTAssertEqual(controller.player.control, .pausing)
        XCTAssertEqual(controller.player.current, position, accuracy: 0.06)
        controller.play()
        eventually("恢复应从原位置推进") { controller.player.current > position + 0.1 }
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
        XCTAssertNil(controller.player.resource)
        XCTAssertNil(controller.boost)
    }

    /// 加载期间以最新增强设置为准；暂停/停止取消后迟到的加载不能起播。
    func testBoostPageHonorsLatestPreferenceAndCancellation() {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.play()
        controller.setBoostEnabled(true)
        controller.pause()
        pump(0.2)
        XCTAssertNil(controller.player.resource)
        controller.play()
        defer { controller.stop() }
        eventually("恢复后的资源使用最新的 2 倍选择") { controller.boost?.isEnabled == true && (controller.boost?.boostedFrames ?? 0) > 4096 }
        controller.stop()
        controller.play()
        controller.stop()
        pump(0.2)
        XCTAssertNil(controller.player.resource)
        XCTAssertNil(controller.boost)
    }

    /// 反复创建 tap 后停止并释放页面，系统最终 finalize 所有 C 状态。
    func testBoostPageReleasesTapContextsAndCancelledPage() {
        let baseline = AudioMixVolumeBoost.liveContexts
        for _ in 0..<5 {
            autoreleasepool {
                let controller = AudioMixExampleController(url: audio)
                controller.loadViewIfNeeded()
                controller.play()
                eventually("tap 应实际工作后再停止") { (controller.boost?.processedFrames ?? 0) > 0 }
                controller.stop()
            }
        }
        weak var released: AudioMixExampleController?
        autoreleasepool {
            var controller: AudioMixExampleController? = AudioMixExampleController(url: audio)
            controller?.loadViewIfNeeded()
            controller?.play()
            released = controller
            controller = nil
        }
        eventually("异步准备不能保留页面") { released == nil }
        eventually("停止后所有 tap 状态应释放") { AudioMixVolumeBoost.liveContexts == baseline }
    }

    /// 资源缺失显示明确错误，切换增强本身不会启动或替换音频。
    func testBoostPageReportsMissingFixture() {
        let controller = AudioMixExampleController(url: nil)
        controller.loadViewIfNeeded()
        controller.setBoostEnabled(true)
        controller.play()
        let status = controller.view.subviews.compactMap { $0 as? UIScrollView }.first?.subviews.compactMap { $0 as? UIStackView }.first?.arrangedSubviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "mix.status" }
        XCTAssertEqual(status?.text, "内置试听音频缺失")
        XCTAssertNil(controller.player.resource)
        XCTAssertNil(controller.boost)
    }

    /// 主播放链路切换增强应保留同一 asset、历史位置、暂停与倍速设置。
    func testManagerBoostPreservesPlaybackAndPreferenceAcrossTracks() throws {
        manager.mode = .single
        manager.setVolumeBoostEnabled(true)
        manager.play(items[0], for: .init(items))
        eventually("主播放应实际执行增强") { (self.manager.volumeBoost?.boostedFrames ?? 0) > 4096 }
        let boost = try XCTUnwrap(manager.volumeBoost)
        let asset = try XCTUnwrap(manager.player.resource as? AVURLAsset)
        manager.player.seek(to: .init(time: 8))
        eventually("寻时应完成") { self.manager.player.current > 8 }
        manager.player.pause()
        manager.player.rate = 1.5
        let position = manager.player.current
        for _ in 0..<5 {
            manager.setVolumeBoostEnabled(false)
            manager.setVolumeBoostEnabled(true)
        }
        pump(0.2)
        XCTAssertTrue(manager.volumeBoost === boost)
        XCTAssertTrue((manager.player.resource as? AVURLAsset) === asset)
        XCTAssertEqual(manager.player.current, position, accuracy: 0.1)
        XCTAssertEqual(manager.player.control, .pausing)
        XCTAssertEqual(manager.player.rate, 1.5)
        manager.playNext()
        eventually("下一首继承增强偏好并实际处理") {
            self.manager.volumeBoost !== boost && (self.manager.volumeBoost?.boostedFrames ?? 0) > 4096
        }
        manager.clear()
        XCTAssertNil(manager.volumeBoost)
        XCTAssertNil(manager.player.resource)
    }

    /// HTTP WAV 通过实际 Manager 和 tap 测量输出，不以开关或配置值代替生效证据。
    func testManagerHTTPWAVBoostActuallyProcessesPCM() throws {
        try verifyHTTPBoost(file: audio, path: "audio.wav")
    }

    /// 压缩网络文件先由 AVFoundation 解码，再进入同一增强处理链。
    func testManagerHTTPAACBoostActuallyProcessesPCM() throws {
        try verifyHTTPBoost(file: PlaybackFixtures.compressedAudio, path: "audio.m4a")
    }

    /// MP3 网络文件也必须实际触发 tap，并验证切换后不回到曲首。
    func testManagerHTTPMP3BoostActuallyProcessesPCM() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "tone", withExtension: "mp3", subdirectory: "Fixtures"))
        try verifyHTTPBoost(file: file, path: "audio.mp3")
    }

    /// 延迟的旧网络资源即使加载完成，也不能把 tap 装到后来切换的本地资源。
    func testManagerBoostCancelsStaleNetworkPreparation() throws {
        let server = try AudioHTTPServer(data: Data(contentsOf: audio))
        defer { server.stop() }
        server.responseDelay = 0.4
        eventually("服务应就绪") { server.port != nil }
        let old = makeItem(server.url("audio.wav"))
        items.append(old)
        manager.play(old, for: .init(items))
        manager.setVolumeBoostEnabled(true)
        manager.play(items[0], for: .init(items))
        eventually("新资源应增强播放") { (self.manager.volumeBoost?.boostedFrames ?? 0) > 4096 }
        let boost = manager.volumeBoost
        pump(0.6)
        XCTAssertEqual(manager.item?.id, items[0].id)
        XCTAssertTrue(manager.volumeBoost === boost)
        manager.clear()
        manager.play(old, for: .init(items))
        manager.clear()
        pump(0.6)
        XCTAssertNil(manager.volumeBoost)
        XCTAssertNil(manager.player.resource)
    }

    /// mix 案例验证参数与时间包络，同时保证切换不影响进度和暂停状态。
    func testMixExamplesApplyEnvelopesWithoutRestartingPlayback() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        defer { controller.stop() }
        controller.play()
        eventually("先实际播放") { controller.player.current > 0.3 }
        controller.pause()
        let position = controller.player.current
        let resource = try XCTUnwrap(controller.player.resource as? AVAudioPlayerResource)
        let capability = try XCTUnwrap(controller.player as? AVAudioMixControlling)
        for example in AudioMixExampleController.Example.allCases {
            controller.selectExample(example)
            XCTAssertTrue((controller.player.resource as? AVAudioPlayerResource)?.asset === resource.asset)
            XCTAssertEqual(controller.player.current, position, accuracy: 0.05)
            XCTAssertEqual(controller.player.control, .pausing)
            if example == .original { XCTAssertNil(capability.audioMix); continue }
            let parameters = try XCTUnwrap(capability.audioMix?.inputParameters.first)
            if example == .boost || example == .silence { XCTAssertNotNil(parameters.audioTapProcessor); continue }
            var start: Float = 0
            var end: Float = 0
            var range = CMTimeRange.zero
            XCTAssertTrue(parameters.getVolumeRamp(for: CMTime(seconds: position + 0.1, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
            switch example {
            case .quiet:
                XCTAssertEqual(start, 0.25, accuracy: 0.001)
            case .fadeIn:
                XCTAssertEqual(start, 0)
                XCTAssertEqual(end, 1)
                XCTAssertEqual(range.start.seconds, position, accuracy: 0.01)
                XCTAssertEqual(range.duration.seconds, 5, accuracy: 0.01)
            case .duck:
                XCTAssertEqual(start, 1)
                XCTAssertEqual(end, 0)
                XCTAssertTrue(parameters.getVolumeRamp(for: CMTime(seconds: position + 2.1, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
                XCTAssertEqual(start, 0)
                XCTAssertEqual(end, 1)
                XCTAssertEqual(range.duration.seconds, 2, accuracy: 0.01)
            default: break
            }
        }
        controller.play()
        eventually("切换后仍应正常推进") { controller.player.current > position + 0.2 }
    }

    /// 加载中的案例选择取最新值，停止后旧异步结果不能恢复音频。
    func testMixExampleSelectionDuringPreparationUsesLatestMode() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        defer { controller.stop() }
        controller.play()
        controller.selectExample(.quiet)
        eventually("最新案例应提交") { controller.player.resource != nil }
        let capability = try XCTUnwrap(controller.player as? AVAudioMixControlling)
        let parameters = try XCTUnwrap(capability.audioMix?.inputParameters.first)
        var start: Float = 0
        var end: Float = 0
        var range = CMTimeRange.zero
        XCTAssertTrue(parameters.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0.25, accuracy: 0.001)
        controller.stop()
        controller.play()
        controller.selectExample(.original)
        controller.stop()
        pump(0.2)
        XCTAssertNil(controller.player.resource)
        XCTAssertNil(controller.boost)
    }

    /// 共享网络验证：要求请求已发生、tap 已处理以及 1→2→1 的真实峰值变化。
    private func verifyHTTPBoost(file: URL, path: String) throws {
        let server = try AudioHTTPServer(data: Data(contentsOf: file))
        defer { manager.clear(); server.stop() }
        eventually("HTTP 服务应就绪") { server.port != nil }
        let item = makeItem(server.url(path))
        items.append(item)
        manager.play(item, for: .init([item]))
        eventually("网络音频必须实际进入 tap", timeout: 15) { (self.manager.volumeBoost?.processedFrames ?? 0) > 4096 }
        let boost = try XCTUnwrap(manager.volumeBoost)
        XCTAssertGreaterThan(server.requests, 0)
        XCTAssertTrue(boost.isSupported)
        eventually("网络原音峰值为 1 倍") { abs((boost.measuredGain ?? 0) - 1) < 0.03 }
        let asset = manager.player.resource as? AVURLAsset
        let before = manager.player.current
        manager.setVolumeBoostEnabled(true)
        eventually("网络增强峰值必须达到 2 倍", timeout: 15) { boost.boostedFrames > 4096 && abs((boost.measuredGain ?? 0) - 2) < 0.03 }
        XCTAssertTrue((manager.player.resource as? AVURLAsset) === asset)
        // tap 可提前处理排队音频，增益测量成功不代表播放时钟已推进。
        eventually("网络播放时钟应继续推进") { self.manager.player.current > before + 0.1 }
        manager.player.pause()
        let paused = manager.player.current
        manager.setVolumeBoostEnabled(false)
        pump(0.2)
        XCTAssertEqual(manager.player.control, .pausing)
        XCTAssertEqual(manager.player.current, paused, accuracy: 0.1)
        manager.player.play()
        eventually("关闭增强应恢复 1 倍", timeout: 15) { abs((boost.measuredGain ?? 0) - 1) < 0.03 }
    }

    /// 通过原播放页真实 UISwitch 事件驱动增强，验证 UI 与共享管理器没有断链。
    func testOriginalPlaybackPageSwitchControlsCurrentResource() throws {
        let shared = AudioPlayerManager.shared
        let item = makeItem(audio)
        items.append(item)
        shared.clear()
        shared.setVolumeBoostEnabled(false)
        defer { shared.clear(); shared.setVolumeBoostEnabled(false) }
        shared.play(item, for: .init([item]))
        let controller = AudioPlayerController.instance()
        controller.loadViewIfNeeded()
        controller.view.frame = UIScreen.main.bounds
        controller.view.layoutIfNeeded()
        let toggle = try XCTUnwrap(findBoostSwitch(in: controller.view))
        XCTAssertFalse(toggle.isOn)
        eventually("主页面当前音频应处理 PCM") { (shared.volumeBoost?.processedFrames ?? 0) > 4096 }
        let resource = try XCTUnwrap(shared.player.resource as? AVURLAsset)
        shared.player.pause()
        let position = shared.player.current
        toggle.isOn = true
        toggle.sendActions(for: .valueChanged)
        XCTAssertTrue(shared.isVolumeBoostEnabled)
        XCTAssertTrue(shared.volumeBoost?.isEnabled == true)
        XCTAssertTrue((shared.player.resource as? AVURLAsset) === resource)
        pump(0.2)
        XCTAssertEqual(shared.player.control, .pausing)
        XCTAssertEqual(shared.player.current, position, accuracy: 0.1)
        toggle.isOn = false
        toggle.sendActions(for: .valueChanged)
        XCTAssertFalse(shared.isVolumeBoostEnabled)
        // 作者与进度之间的新增控件应位于可见画面内，保留原播放按钮的操作区域。
        let frame = toggle.convert(toggle.bounds, to: controller.view)
        XCTAssertTrue(controller.view.bounds.contains(frame))
        let playerView = try XCTUnwrap(controller.view as? AudioPlayerView)
        XCTAssertLessThan(frame.maxY, playerView.slider.convert(playerView.slider.bounds, to: controller.view).minY)
    }

    /// 沿真实视图树查找开关，使用稳定标识而不依赖堆栈视图的层级数量。
    private func findBoostSwitch(in view: UIView) -> UISwitch? {
        if view.accessibilityIdentifier == "player.boost" { return view as? UISwitch }
        return view.subviews.compactMap { findBoostSwitch(in: $0) }.first
    }

    /// 用随机标识隔离 UserDefaults 播放记录，避免影响手工 Demo 数据。
    private func makeItem(_ url: URL) -> AudioPlayerItem {
        return .init(id: UUID().uuidString, title: "测试单集", cover: "", author: "测试", duration: 24, resource: url)
    }
}

/// 静音案例覆盖检测时间线与真实 AVPlayer/tap 链路；与既有集成测试共用串行音频环境。
extension DemoIntegrationTests {
    /// 连续确认与观测时效均须满足；不能以远处静音判定当前位置。
    func testSilenceTimelineRequiresFreshConfirmedWindows() {
        var timeline = AudioMixSilenceTimeline()
        for index in 0..<100 {
            timeline.append(start: Double(index) * 0.02, end: Double(index + 1) * 0.02, rms: 0, peak: 0, streamID: 1)
        }
        XCTAssertFalse(timeline.canAccelerate(at: 0.29))
        XCTAssertTrue(timeline.canAccelerate(at: 1.9))
        XCTAssertTrue(timeline.canAccelerate(at: 1.7), "已确认的同一连续静音段不应因前瞻较多而撤销")
        XCTAssertFalse(timeline.canAccelerate(at: 3))
        timeline.append(start: 2, end: 2.02, rms: 0.03, peak: 0.04, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 2))
    }

    /// 峰值保护、时间缺口、重新协商流和无效时间都必须保守退出。
    func testSilenceTimelineRejectsUnsafeEvidence() {
        var timeline = AudioMixSilenceTimeline()
        timeline.append(start: 0, end: 2, rms: 0.0009, peak: 0.0013, streamID: 1)
        XCTAssertTrue(timeline.canAccelerate(at: 1.9))
        timeline.append(start: 3, end: 4, rms: 0, peak: 0, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 1))
        timeline.append(start: 4, end: 5, rms: 0, peak: 0.01, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 4.4))
        timeline.append(start: 5, end: 6, rms: 0, peak: 0, streamID: 2)
        XCTAssertFalse(timeline.canAccelerate(at: 3.5))
        timeline.append(start: .nan, end: 7, rms: 0, peak: 0, streamID: 2)
        XCTAssertTrue(timeline.ranges.isEmpty)
    }

    /// 真实 PCM 四种开关组合：增益不改变检测，静音开关不改变 mix、asset 或进度。
    func testSilenceAndBoostSwitchesAreIndependentDuringPlayback() throws {
        let url = try AudioMixSilenceSample.make(quietAmplitude: 0.0013)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.play()
        defer { controller.stop() }
        eventually("原音、无加速应实际处理") { (controller.boost?.processedFrames ?? 0) > 4096 }
        let boost = try XCTUnwrap(controller.boost)
        let resource = try XCTUnwrap(controller.player.resource as? AVAudioPlayerResource)
        XCTAssertEqual(controller.player.rate, 1)
        controller.setBoostEnabled(true)
        eventually("仅增强应实际达到 2 倍") { abs((boost.measuredGain ?? 0) - 2) < 0.03 }
        XCTAssertEqual(controller.player.rate, 1)
        controller.setSilenceAccelerationEnabled(true)
        eventually("增强与静音同时开启，应进入真实静音区加速", timeout: 10) { controller.silenceAcceleration.isAccelerating }
        XCTAssertGreaterThan(controller.player.current, 2.2)
        XCTAssertLessThan(controller.player.current, 6)
        controller.setBoostEnabled(false)
        eventually("仅静音开启时原音 PCM 保持 1 倍") { abs((boost.measuredGain ?? 0) - 1) < 0.03 }
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
        XCTAssertTrue(controller.boost === boost)
        XCTAssertTrue((controller.player.resource as? AVAudioPlayerResource)?.asset === resource.asset)
        controller.setSilenceAccelerationEnabled(false)
        XCTAssertEqual(controller.player.rate, 1)
        XCTAssertFalse(boost.isEnabled)
        controller.setSilenceAccelerationEnabled(true)
        eventually("到有声区必须恢复用户倍速", timeout: 10) { controller.player.current > 6.1 && controller.player.current < 7.8 && !controller.silenceAcceleration.isAccelerating }
    }

    /// 暂停、seek、案例切换和停止都不能遗留临时倍速或意外起播。
    func testSilenceAccelerationRestoresUserRateAndPlaybackIntent() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setUserRate(1.5)
        controller.setSilenceAccelerationEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("静音应按当前媒体能力使用最快目标倍率", timeout: 10) { controller.silenceAcceleration.isAccelerating }
        XCTAssertEqual(controller.player.rate, expectedSilenceRate(controller.player))
        controller.pause()
        XCTAssertEqual(controller.player.rate, 1.5)
        let position = controller.player.current
        controller.setBoostEnabled(true)
        controller.setSilenceAccelerationEnabled(false)
        controller.setSilenceAccelerationEnabled(true)
        pump(0.2)
        XCTAssertEqual(controller.player.control, .pausing)
        XCTAssertEqual(controller.player.current, position, accuracy: 0.1)
        controller.player.seek(to: .init(time: 0.5))
        eventually("seek 后旧静音证据应清除") { abs(controller.player.current - 0.5) < 0.1 }
        XCTAssertEqual(controller.player.rate, 1.5)
        controller.play()
        eventually("有声段保持用户速率") { controller.player.current > 0.7 }
        XCTAssertFalse(controller.silenceAcceleration.isAccelerating)
        controller.selectExample(.quiet)
        XCTAssertEqual(controller.player.rate, 1.5)
        controller.stop()
        XCTAssertEqual(controller.player.rate, 1.5)
        XCTAssertNil(controller.boost)
    }

    /// 左声道静音不能掩盖右声道的有效声音；检测必须覆盖每个声道。
    func testSilenceDetectorProtectsRightChannelSound() throws {
        let url = try AudioMixSilenceSample.make(rightChannelOnly: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setSilenceAccelerationEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("右声道信号应进入 tap") { (controller.boost?.silenceTimeline.analyzedUntil ?? 0) > 1 }
        XCTAssertFalse(controller.boost?.silenceTimeline.canAccelerate(at: 0.5) ?? true)
        XCTAssertEqual(controller.silenceAcceleration.accelerationCount, 0)
    }

    /// HTTP 文件实际解码后也可检测静音；不以本地样本结果推断网络处理成功。
    func testHTTPSilenceAccelerationActuallyProcessesPCM() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let server = try AudioHTTPServer(data: Data(contentsOf: url))
        defer { server.stop() }
        eventually("HTTP 服务就绪") { server.port != nil }
        let controller = AudioMixExampleController(url: server.url("audio.wav"))
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setSilenceAccelerationEnabled(true)
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("HTTP tap 应实际进入静音加速", timeout: 15) { controller.silenceAcceleration.isAccelerating }
        XCTAssertGreaterThan(server.requests, 0)
        XCTAssertGreaterThan(controller.boost?.boostedFrames ?? 0, 4096)
        controller.pause()
        XCTAssertEqual(controller.player.rate, 1)
    }

    /// 样本生成和异步准备取消后不能迟到起播；最新两个开关偏好在重试时保留。
    func testSilenceSampleCancellationAndLatestPreferences() {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.loadSilenceSample()
        controller.stop()
        pump(0.3)
        XCTAssertNil(controller.player.resource)
        controller.loadSilenceSample()
        controller.setBoostEnabled(true)
        controller.setSilenceAccelerationEnabled(true)
        defer { controller.stop() }
        eventually("新样本应使用加载期间最新的独立偏好") { (controller.boost?.boostedFrames ?? 0) > 4096 }
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
    }

    /// 界面事件必须分别接到两个偏好；暂停时修改控件不能意外起播。
    func testSilencePageControlsDriveIndependentPreferences() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.play()
        defer { controller.stop() }
        eventually("页面资源应就绪") { (controller.boost?.processedFrames ?? 0) > 4096 }
        controller.pause()
        let position = controller.player.current
        let toggle = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.silence") as? UISwitch)
        let boost = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.boost") as? UISegmentedControl)
        toggle.isOn = true
        toggle.sendActions(for: .valueChanged)
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
        XCTAssertFalse(controller.isBoostEnabled)
        boost.selectedSegmentIndex = 1
        boost.sendActions(for: .valueChanged)
        XCTAssertTrue(controller.boost?.isEnabled == true)
        toggle.isOn = false
        toggle.sendActions(for: .valueChanged)
        XCTAssertFalse(controller.silenceAcceleration.isEnabled)
        XCTAssertTrue(controller.isBoostEnabled)
        pump(0.2)
        XCTAssertEqual(controller.player.current, position, accuracy: 0.1)
        XCTAssertEqual(controller.player.control, .pausing)
    }

    /// 静音定时器不得保留页面或 tap；未显式停止的页面销毁也应完整释放。
    func testSilencePageReleasesTimerAndTap() {
        let baseline = AudioMixVolumeBoost.liveContexts
        weak var released: AudioMixExampleController?
        weak var driver: AudioMixSilenceAcceleration?
        autoreleasepool {
            var controller: AudioMixExampleController? = AudioMixExampleController(url: audio)
            controller?.loadViewIfNeeded()
            controller?.selectExample(.silence)
            controller?.setSilenceAccelerationEnabled(true)
            controller?.play()
            eventually("销毁前先执行真实检测") { (controller?.boost?.silenceTimeline.analyzedUntil ?? 0) > 0.2 }
            released = controller
            driver = controller?.silenceAcceleration
            controller = nil
        }
        eventually("页面与静音驱动器应释放") { released == nil && driver == nil }
        eventually("静音 tap 状态应释放") { AudioMixVolumeBoost.liveContexts == baseline }
    }

    /// 低噪声滞回可稳定延伸静音，峰值或有声一旦出现必须立即撤销。
    func testSilenceTimelineHysteresisAndSoundExit() {
        var timeline = AudioMixSilenceTimeline()
        timeline.append(start: 0, end: 0.4, rms: 0.0009, peak: 0.0013, streamID: 1)
        timeline.append(start: 0.4, end: 1, rms: 0.0014, peak: 0.002, streamID: 1)
        XCTAssertTrue(timeline.canAccelerate(at: 0.9))
        timeline.append(start: 1, end: 1.02, rms: 0.002, peak: 0.003, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 1))
        timeline.append(start: 1.02, end: 1.5, rms: 0.0014, peak: 0.002, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 1.4))
    }

    /// 媒体进度冻结时也必须按真实经过时间淘汰静音证据，不能无限沿用旧块。
    func testSilenceTimelineExpiresWhileMediaClockIsFrozen() {
        var timeline = AudioMixSilenceTimeline()
        timeline.append(start: 0, end: 1, rms: 0, peak: 0, streamID: 1, observedAt: 10)
        XCTAssertTrue(timeline.canAccelerate(at: 0.9, now: 10.2))
        XCTAssertFalse(timeline.canAccelerate(at: 0.9, now: 10.3))
        XCTAssertFalse(timeline.canAccelerate(at: 0.9, now: 9))
    }

    /// 关闭功能与切到包络对比均停止分析；实时模式下音量增强仍可独立工作。
    func testDisabledSilenceDetectionDoesNotAnalyzePCM() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("仅增强仍应处理 PCM") { (controller.boost?.boostedFrames ?? 0) > 4096 }
        pump(0.2)
        let boost = try XCTUnwrap(controller.boost)
        XCTAssertEqual(boost.silenceTimeline.analyzedUntil, 0)
        controller.selectExample(.silence)
        controller.setSilenceAccelerationEnabled(true)
        eventually("单独开启静音才开始分析") { boost.silenceTimeline.analyzedUntil > 0 }
        controller.setSilenceAccelerationEnabled(false)
        pump(0.3)
        XCTAssertEqual(boost.silenceTimeline.analyzedUntil, 0)
        XCTAssertTrue(boost.isEnabled)
        controller.setSilenceAccelerationEnabled(true)
        eventually("重新开启可获取新观测") { boost.silenceTimeline.analyzedUntil > 0 }
        controller.selectExample(.original)
        pump(0.3)
        XCTAssertEqual(boost.silenceTimeline.analyzedUntil, 0)
        XCTAssertTrue(boost.isEnabled)
    }

    /// 一个连续静音段只应稳定进入一次加速；自然结束重播应重新绑定并保留偏好。
    func testSilenceAccelerationRemainsStableAndReplays() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setUserRate(1.5)
        controller.setSilenceAccelerationEnabled(true)
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("应越过第一段静音恢复有声", timeout: 10) { controller.player.current > 6.3 }
        XCTAssertEqual(controller.silenceAcceleration.accelerationCount, 1, "连续静音不应因临时调速反复进出加速")
        eventually("静音样本应自然结束", timeout: 10) {
            if case .finished = controller.player.state { return true }
            return false
        }
        XCTAssertEqual(controller.player.rate, 1.5)
        XCTAssertFalse(controller.boost?.isSilenceDetectionEnabled ?? true)
        let resource = try XCTUnwrap(controller.player.resource as? AVAudioPlayerResource)
        controller.play()
        eventually("重播后检测应重新工作") { (controller.boost?.silenceTimeline.analyzedUntil ?? 0) > 0.3 && controller.player.current < 2 }
        XCTAssertTrue((controller.player.resource as? AVAudioPlayerResource)?.asset === resource.asset)
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
        XCTAssertTrue(controller.boost?.isEnabled == true)
    }

    /// 一轮批量消费中即使有声后紧接静音，也不能沿用上一段的加速许可。
    func testSilenceContinuationCannotHideSoundInsideOneBatch() {
        var timeline = AudioMixSilenceTimeline()
        timeline.append(start: 0, end: 1, rms: 0, peak: 0, streamID: 1)
        XCTAssertTrue(timeline.canAccelerate(at: 0.9))
        let generation = timeline.soundGeneration
        let continuity = timeline.continuityGeneration
        XCTAssertTrue(timeline.canAccelerate(at: 0.9, continuingAfter: generation, continuingIn: continuity))
        timeline.append(start: 1, end: 1.02, rms: 0.02, peak: 0.04, streamID: 1)
        timeline.append(start: 1.02, end: 1.04, rms: 0, peak: 0, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 1.04, continuingAfter: generation, continuingIn: continuity), "批量读取不能让末尾静音覆盖中间的有声窗口")
    }

    /// 控件标识稳定，测试不依赖滚动堆栈的具体嵌套层级。
    private func findMixControl(in view: UIView, identifier: String) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.compactMap { findMixControl(in: $0, identifier: identifier) }.first
    }

}

/// 第二轮真机验证补齐压缩网络文件、会话策略和连续操作与静音调速的组合。
extension DemoIntegrationTests {
    /// MP3 经 HTTP 解码后确实触发静音加速，并在有声段恢复基础速率。
    func testHTTPMP3SilenceAcceleration() throws {
        try verifyCompressedSilence(extension: "mp3")
    }

    /// AAC/M4A 使用相同信号，不能以 WAV 的 tap 结果推断压缩格式也工作。
    func testHTTPAACSilenceAcceleration() throws {
        try verifyCompressedSilence(extension: "m4a")
    }

    /// 检查真实网络请求、PCM 处理、临时速率和有声退出，不只检查开关状态。
    private func verifyCompressedSilence(extension suffix: String) throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "silence", withExtension: suffix, subdirectory: "Fixtures"))
        let server = try AudioHTTPServer(data: Data(contentsOf: url))
        defer { server.stop() }
        eventually("压缩文件服务就绪") { server.port != nil }
        let controller = AudioMixExampleController(url: server.url("audio." + suffix))
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setSilenceAccelerationEnabled(true)
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("压缩 HTTP 音频应实际加速", timeout: 15) { controller.silenceAcceleration.isAccelerating }
        XCTAssertGreaterThan(server.requests, 0)
        XCTAssertGreaterThan(controller.boost?.boostedFrames ?? 0, 4096)
        XCTAssertEqual(controller.player.rate, expectedSilenceRate(controller.player), accuracy: 0.001)
        // HTTP 解码路径同样采样媒体时钟，不能只靠写入的目标速率证明执行成功。
        eventually("等待 HTTP 静音中部") { controller.silenceAcceleration.isAccelerating && controller.player.current > 2.8 && controller.player.current < 4.5 }
        let target = expectedSilenceRate(controller.player)
        let mediaStart = controller.player.current
        let clockStart = ProcessInfo.processInfo.systemUptime
        pump(0.3)
        let measured = (controller.player.current - mediaStart) / (ProcessInfo.processInfo.systemUptime - clockStart)
        let measurement = XCTAttachment(string: "HTTP \(suffix): target=\(target), media/uptime=\(measured)")
        measurement.lifetime = .keepAlways
        add(measurement)
        XCTAssertEqual(controller.player.control, .playing)
        XCTAssertEqual(controller.player.loading, .ended)
        XCTAssertTrue(controller.silenceAcceleration.isAccelerating)
        XCTAssertLessThan(controller.player.current, 6)
        XCTAssertEqual(measured, target, accuracy: 0.35)
        eventually("压缩音频恢复有声后应退出加速", timeout: 8) {
            controller.player.current > 6.2 && controller.player.current < 7.8 && !controller.silenceAcceleration.isAccelerating
        }
        XCTAssertEqual(controller.player.rate, 1)
    }

    /// 中断期间临时速率必须撤销；恢复许可不能覆盖用户在中断中的主动暂停。
    func testSilenceInterruptionAndRoutePolicies() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setSilenceAccelerationEnabled(true)
        controller.setBoostEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("中断前先真实加速") { controller.silenceAcceleration.isAccelerating }
        postSilenceInterruption(.began)
        eventually("中断撤销临时倍速") { controller.player.control == .pausing && controller.player.rate == 1 }
        postSilenceInterruption(.ended, options: .shouldResume)
        eventually("有恢复许可时继续真实播放") { controller.player.control == .playing && controller.silenceAcceleration.isAccelerating }
        postSilenceInterruption(.began)
        eventually("再次中断暂停") { controller.player.control == .pausing }
        controller.pause()
        postSilenceInterruption(.ended, options: .shouldResume)
        pump(0.3)
        XCTAssertEqual(controller.player.control, .pausing)
        XCTAssertEqual(controller.player.rate, 1)
        controller.play()
        eventually("用户继续后重新播放") { controller.player.control == .playing }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        eventually("输出不可用时保持暂停和基础倍速") { controller.player.control == .pausing && controller.player.rate == 1 }
        XCTAssertTrue(controller.boost?.isEnabled == true)
        let processor = try XCTUnwrap(controller.boost)
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance())
        eventually("服务重置后释放当前资源并停检测") {
            if case .failed = controller.player.state { return controller.player.resource == nil && !processor.isSilenceDetectionEnabled }
            return false
        }
    }

    /// 这里只注入系统同格式通知验证策略，不代表真实电话、蓝牙断连或音频服务崩溃。
    private func postSilenceInterruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) {
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue, AVAudioSessionInterruptionOptionKey: options.rawValue])
    }

    /// 用户 2× 时按媒体能力加速、非法值拒绝、快速双开关及连续 seek 后不能丢用户速率或意外起播。
    func testSilenceRateLimitsAndRapidOperations() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setSilenceAccelerationEnabled(true)
        controller.setUserRate(2)
        controller.play()
        defer { controller.stop() }
        eventually("用户 2 倍进入静音段") { controller.player.current > 2.5 }
        let target = expectedSilenceRate(controller.player)
        eventually("用户 2 倍也应按媒体能力选择静音目标") { controller.player.rate == target }
        XCTAssertEqual(controller.silenceAcceleration.isAccelerating, target > 2)
        controller.pause()
        let resource = try XCTUnwrap(controller.player.resource as? AVAudioPlayerResource)
        for index in 0..<30 {
            controller.setBoostEnabled(index % 2 == 0)
            controller.setSilenceAccelerationEnabled(index % 3 == 0)
            controller.setUserRate([0.5, 1, 1.5][index % 3])
            controller.player.seek(to: .init(time: Double(index % 5) + 0.5))
        }
        controller.setUserRate(0.5)
        for invalid in [Double.nan, .infinity, 0, 2.1] { controller.setUserRate(invalid) }
        controller.player.seek(to: .init(time: 0.5))
        eventually("最后一次 seek 应生效") { abs(controller.player.current - 0.5) < 0.1 }
        pump(0.3)
        XCTAssertEqual(controller.player.control, .pausing)
        XCTAssertEqual(controller.player.rate, 0.5)
        XCTAssertTrue((controller.player.resource as? AVAudioPlayerResource)?.asset === resource.asset)
        controller.setSilenceAccelerationEnabled(true)
        controller.play()
        eventually("慢速有声段应正常推进") { controller.player.current > 0.7 }
        XCTAssertFalse(controller.silenceAcceleration.isAccelerating)
        XCTAssertEqual(controller.player.rate, 0.5)
    }

    /// 分块 MP3 必须收到系统真实卡顿通知；恢复供数和用户暂停两条路径都验证底层速率。
    func testSilenceRealBufferExhaustionAndRecovery() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "silence", withExtension: "mp3", subdirectory: "Fixtures"))
        let server = try AudioHTTPServer(data: Data(contentsOf: url))
        defer { server.stop() }
        server.chunkInterval = 0.1
        server.chunkSize = 4096
        eventually("分块静音服务就绪") { server.port != nil }
        let asset = AVURLAsset(url: server.url("audio.mp3"))
        // 测试单独加载 HTTP 音轨后再绑定真实引擎，便于观察底层 AVPlayer 的卡顿通知和 rate。
        var loadedTracks: [AVAssetTrack]?
        var loadError: Error?
        let task = Task {
            do { loadedTracks = try await asset.loadTracks(withMediaType: .audio) }
            catch { loadError = error }
        }
        defer { task.cancel() }
        eventually("网络音轨应加载完成", timeout: 15) { loadedTracks != nil || loadError != nil }
        XCTAssertNil(loadError)
        let boost = try AudioMixVolumeBoost(tracks: XCTUnwrap(loadedTracks))
        boost.setEnabled(true)
        let player = AVPlayer()
        var configuration = AudioPlayerConfiguration()
        configuration.isAutoplay = false
        configuration.preferredBufferDuration = 1
        engine.stop()
        engine = AudioPlayerAVEngine(configuration, player: player)
        let driver = AudioMixSilenceAcceleration(player: engine)
        driver.bind(boost)
        driver.setEnabled(true)
        defer { driver.stop(); engine.stop() }
        engine.prepare(resource: AVAudioPlayerResource(asset: asset, audioMix: boost.mix))
        engine.play()
        eventually("卡顿前应先实际加速", timeout: 15) { driver.isAccelerating }
        var stalls = 0
        let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: player.currentItem, queue: .main) { _ in stalls += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        server.suspended = true
        eventually("停止供数必须触发真实卡顿", timeout: 25) { stalls > 0 }
        eventually("卡顿后应撤销静音加速") { !driver.isAccelerating && self.engine.rate == 1 }
        server.suspended = false
        let position = engine.current
        eventually("恢复供数后应继续播放", timeout: 15) { self.engine.current > position + 0.3 && player.rate > 0 }
        server.suspended = true
        let previousStalls = stalls
        eventually("第二次耗尽缓冲", timeout: 25) { stalls > previousStalls }
        engine.pause()
        server.suspended = false
        pump(2)
        let paused = engine.current
        pump(0.4)
        XCTAssertEqual(engine.current, paused, accuracy: 0.1)
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertFalse(driver.isAccelerating)
        XCTAssertTrue(boost.isEnabled)
    }

    /// 没有声音也不意味着可跨缺口沿用许可；新流和丢窗都必须重新连续确认 300ms。
    func testSilenceContinuationRejectsDiscontinuousEvidence() {
        var timeline = AudioMixSilenceTimeline()
        timeline.append(start: 0, end: 1, rms: 0, peak: 0, streamID: 1)
        let generation = timeline.soundGeneration
        let continuity = timeline.continuityGeneration
        timeline.append(start: 3, end: 3.02, rms: 0, peak: 0, streamID: 1)
        XCTAssertFalse(timeline.canAccelerate(at: 3.02, continuingAfter: generation, continuingIn: continuity))
        timeline.append(start: 3.02, end: 3.04, rms: 0, peak: 0, streamID: 2)
        XCTAssertFalse(timeline.canAccelerate(at: 3.04, continuingAfter: generation, continuingIn: continuity))
    }
}

/// 慢速基础速率也需要稳定调速，不能只覆盖界面默认 1× 的重配置时序。
extension DemoIntegrationTests {
    /// 基础 0.5× 在静音时使用媒体允许的 3× 或 2×；整段内不应反复切换，关闭后准确恢复 0.5×。
    func testSilenceSlowUserRateRemainsStable() throws {
        let url = try AudioMixSilenceSample.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AudioMixExampleController(url: url)
        controller.loadViewIfNeeded()
        controller.selectExample(.silence)
        controller.setUserRate(0.5)
        controller.setSilenceAccelerationEnabled(true)
        controller.play()
        defer { controller.stop() }
        eventually("慢速资源应就绪") { (controller.boost?.processedFrames ?? 0) > 4096 }
        controller.player.seek(to: .init(time: 2.1))
        eventually("慢速静音应触发额外速率") { controller.silenceAcceleration.isAccelerating }
        XCTAssertEqual(controller.player.rate, expectedSilenceRate(controller.player), accuracy: 0.001)
        eventually("慢速静音持续推进") { controller.player.current > 4.5 }
        XCTAssertEqual(controller.silenceAcceleration.accelerationCount, 1)
        controller.setSilenceAccelerationEnabled(false)
        XCTAssertEqual(controller.player.rate, 0.5)
    }
}

/// 冷启动不能依赖主列表提前配置过音频会话。
extension DemoIntegrationTests {
    /// 先恢复系统默认环境，再直接播放独立页；宿主必须选择支持后台的 playback 类别。
    func testMixColdStartConfiguresPlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false)
        try session.setCategory(.ambient)
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.play()
        defer { controller.stop() }
        eventually("冷启动独立页应实际处理 PCM") { (controller.boost?.processedFrames ?? 0) > 4096 }
        XCTAssertEqual(session.category, .playback)
        controller.pause()
        let position = controller.player.current
        pump(0.2)
        XCTAssertEqual(controller.player.current, position, accuracy: 0.1)
        controller.play()
        eventually("激活会话后仍从暂停位置恢复") { controller.player.current > position + 0.2 }
    }
}

/// 最快静音倍率与缓冲边界可确定性验证，不依赖测试时的网络速度。
extension DemoIntegrationTests {
    /// 实际播放测试根据当前 item 的系统能力断言；读取不到能力必须失败，不能悄悄放宽预期。
    private func expectedSilenceRate(_ player: AudioPlayerable) -> Double {
        let capacity = (player as? AVAudioPlaybackMonitoring)?.playbackCapacity
        XCTAssertNotNil(capacity)
        return capacity?.canPlayFastForward == true ? 3 : 2
    }

    /// 3× 优先、2× 兼容回退均独立于用户的基础倍速；未知能力不额外提速。
    func testSilenceMaximumRateAndCapabilityFallback() {
        for base in [0.5, 1, 1.5, 2] {
            for fast in [false, true] {
                let capacity = AVAudioPlaybackCapacity(canPlayFastForward: fast, bufferedDuration: 20, isBufferedToEnd: false)
                XCTAssertEqual(AudioMixSilenceRatePolicy.target(userRate: base, capacity: capacity, continuing: false), fast ? 3 : 2)
            }
            XCTAssertEqual(AudioMixSilenceRatePolicy.target(userRate: base, capacity: nil, continuing: true), base)
        }
    }

    /// 使用目标倍率折算真实时间余量，验证滞回、缓冲耗尽、完整尾段与异常值。
    func testSilenceBufferThresholdsAndHysteresis() {
        for fast in [false, true] {
            let rate = fast ? 3.0 : 2.0
            func target(_ seconds: Double, continuing: Bool = false, toEnd: Bool = false) -> Double {
                AudioMixSilenceRatePolicy.target(userRate: 1, capacity: .init(canPlayFastForward: fast, bufferedDuration: seconds, isBufferedToEnd: toEnd), continuing: continuing)
            }
            XCTAssertEqual(target(rate * 2), rate)
            XCTAssertEqual(target(rate * 2 - 0.01), 1)
            XCTAssertEqual(target(rate, continuing: true), rate)
            XCTAssertEqual(target(rate * 0.5, continuing: true), rate)
            XCTAssertEqual(target(rate * 0.5 - 0.01, continuing: true), 1)
            XCTAssertEqual(target(0, continuing: true), 1)
            XCTAssertEqual(target(0.2, toEnd: true), rate)
            for invalid in [Double.nan, .infinity, -1] { XCTAssertEqual(target(invalid, toEnd: true), 1) }
        }
    }

    /// 快照来自当前 item；本地资源无需依赖网络加载进度，停止后不得保留上一首能力。
    func testAVPlaybackCapacityFollowsItemLifetime() throws {
        XCTAssertNil(engine.playbackCapacity)
        prepare()
        let capacity = try XCTUnwrap(engine.playbackCapacity)
        XCTAssertTrue(capacity.isBufferedToEnd)
        XCTAssertGreaterThan(capacity.bufferedDuration, 1)
        engine.stop()
        XCTAssertNil(engine.playbackCapacity)
    }
}


/// AudioMix 页面交互使用真实控件事件与播放器验证，避免把界面显示当成功能已运行。
extension DemoIntegrationTests {
    /// 默认原音频即可开静音，包络对比中开关可返回实时模式，暂停与 item 身份保持。
    func testMixDefaultControlsAndEnvelopeReturnPreservePlayback() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        let silence = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.silence") as? UISwitch)
        let boost = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.boost") as? UISegmentedControl)
        let examples = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.example") as? UISegmentedControl)
        XCTAssertTrue(silence.isEnabled)
        XCTAssertTrue(boost.isEnabled)
        XCTAssertEqual(examples.numberOfSegments, 5)
        silence.isOn = true
        silence.sendActions(for: .valueChanged)
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
        controller.play()
        defer { controller.stop() }
        eventually("默认实时模式应执行检测") { (controller.boost?.silenceTimeline.analyzedUntil ?? 0) > 0.3 }
        controller.pause()
        let position = controller.player.current
        let resource = try XCTUnwrap(controller.player.resource as? AVAudioPlayerResource)
        for index in 1..<examples.numberOfSegments {
            examples.selectedSegmentIndex = index
            examples.sendActions(for: .valueChanged)
            XCTAssertFalse(controller.silenceAcceleration.isEnabled)
            XCTAssertTrue(controller.isSilenceAccelerationEnabled)
            XCTAssertTrue(silence.isEnabled)
            boost.selectedSegmentIndex = 1
            boost.sendActions(for: .valueChanged)
            XCTAssertEqual(examples.selectedSegmentIndex, 0)
            XCTAssertTrue(controller.silenceAcceleration.isEnabled)
            XCTAssertTrue(controller.isBoostEnabled)
            XCTAssertNotNil((controller.player as? AVAudioMixControlling)?.audioMix?.inputParameters.first?.audioTapProcessor)
            XCTAssertTrue((controller.player.resource as? AVAudioPlayerResource)?.asset === resource.asset)
            XCTAssertEqual(controller.player.current, position, accuracy: 0.05)
            XCTAssertEqual(controller.player.control, .pausing)
        }
        controller.selectExample(.quiet)
        silence.isOn = false
        silence.sendActions(for: .valueChanged)
        XCTAssertEqual(examples.selectedSegmentIndex, 0)
        XCTAssertFalse(controller.silenceAcceleration.isEnabled)
        XCTAssertTrue(controller.isBoostEnabled)
    }

    /// 原资源与合成样本可往返；未知静音位置不 seek，样本快捷 seek 保持暂停与两个独立偏好。
    func testMixSourceComparisonAndSilenceShortcut() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.setBoostEnabled(true)
        controller.setUserRate(1.5)
        controller.play()
        defer { controller.stop() }
        eventually("原资源先播放") { controller.player.current > 0.2 }
        controller.pause()
        let position = controller.player.current
        controller.seekToSilenceSample()
        XCTAssertEqual(controller.player.current, position, accuracy: 0.05)
        XCTAssertEqual(controller.player.control, .pausing)
        controller.loadSilenceSample()
        eventually("样本应开始实际处理") { controller.player.resource?.value != self.audio && (controller.boost?.processedFrames ?? 0) > 4096 }
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
        XCTAssertTrue(controller.isBoostEnabled)
        XCTAssertEqual(controller.silenceAcceleration.userRate, 1.5)
        controller.pause()
        let jump = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.silence.seek") as? UIButton)
        jump.sendActions(for: .touchUpInside)
        eventually("跳转应定位已知静音段") { abs(controller.player.current - 2.1) < 0.1 }
        XCTAssertEqual(controller.player.control, .pausing)
        let original = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.source.original") as? UIButton)
        original.sendActions(for: .touchUpInside)
        eventually("返回进入页面时的资源") { controller.player.resource?.value == self.audio && controller.player.current > 0.1 }
        XCTAssertTrue(controller.silenceAcceleration.isEnabled)
        XCTAssertTrue(controller.isBoostEnabled)
        // 返回原资源也取消迟到样本结果，不能在之后被旧任务换回样本。
        controller.loadSilenceSample()
        controller.loadOriginalSource()
        eventually("取消生成后仍播放原资源") { controller.player.resource?.value == self.audio && controller.player.current > 0.1 }
        pump(0.3)
        XCTAssertEqual(controller.player.resource?.value, audio)
    }

    /// 重放仅重设包络起点，当前进度和暂停不变；显示目标倍率、播放反馈和 PCM 观测。
    func testMixReapplyEnvelopeAndLiveStatus() throws {
        let controller = AudioMixExampleController(url: audio)
        controller.loadViewIfNeeded()
        controller.play()
        defer { controller.stop() }
        eventually("实际 PCM 已处理") { (controller.boost?.processedFrames ?? 0) > 4096 }
        let label = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.processing") as? UILabel)
        eventually("状态区展示目标倍率、播放状态和 PCM 峰值比") { label.text?.contains("当前目标") == true && label.text?.contains("播放中") == true && label.text?.contains("PCM 峰值比") == true }
        controller.selectExample(.quiet)
        XCTAssertTrue(label.text?.contains("25%") == true)
        controller.selectExample(.fadeIn)
        controller.player.seek(to: .init(time: 4))
        eventually("在包络之后移动位置") { controller.player.current > 4 }
        controller.pause()
        let position = controller.player.current
        let button = try XCTUnwrap(findMixControl(in: controller.view, identifier: "mix.reapply") as? UIButton)
        button.sendActions(for: .touchUpInside)
        let parameters = try XCTUnwrap((controller.player as? AVAudioMixControlling)?.audioMix?.inputParameters.first)
        var start: Float = 0
        var end: Float = 0
        var range = CMTimeRange.zero
        XCTAssertTrue(parameters.getVolumeRamp(for: CMTime(seconds: position + 0.1, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(range.start.seconds, position, accuracy: 0.01)
        XCTAssertEqual(start, 0)
        XCTAssertEqual(end, 1)
        XCTAssertEqual(controller.player.current, position, accuracy: 0.05)
        XCTAssertEqual(controller.player.control, .pausing)
    }
}
