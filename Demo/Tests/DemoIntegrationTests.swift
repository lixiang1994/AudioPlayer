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
            if example == .boost { XCTAssertNotNil(parameters.audioTapProcessor); continue }
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
