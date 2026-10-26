import XCTest

/// 从独立 UI 测试进程操纵真实 Demo 和 SpringBoard，不以模拟生命周期通知替代后台操作。
final class DevicePlaybackUITests: XCTestCase {
    /// 每项测试启动独立播放会话，后台停留使用 XCTest 等待以便系统继续处理事件。
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--playback-device-tests"]
    }

    override func tearDown() {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        super.tearDown()
    }

    /// 实际页面暂停、拖动、恢复和上一集/下一集，检查真实媒体位置与标题。
    func testDemoButtonsSeekAndQueue() {
        start()
        app.buttons["playback.toggle"].tap()
        waitForControl("paused")
        app.sliders["playback.seek"].adjust(toNormalizedSliderPosition: 0.3)
        waitUntil("拖动应落到 54 秒附近") { self.time > 50 && self.time < 58 }
        app.buttons["playback.toggle"].tap()
        waitForControl("playing")
        app.buttons["playback.next"].tap()
        XCTAssertTrue(app.staticTexts["真机测试第二集"].waitForExistence(timeout: 5))
        waitUntil("切集应从头播放") { self.time < 5 }
        app.buttons["playback.previous"].tap()
        XCTAssertTrue(app.staticTexts["真机测试第一集"].waitForExistence(timeout: 5))
        waitUntil("返回上一集应恢复记录") { self.time > 50 }
    }

    /// Home 后在真实后台播放六秒，回前台的媒体时间差应证明后台确实在推进。
    func testActualBackgroundPlaybackContinues() {
        start()
        XCUIDevice.shared.press(.home)
        pauseFor(6)
        app.activate()
        waitForControl("playing")
        XCTAssertGreaterThan(backgroundDelta, 4)
    }

    /// 禁止后台播放时，Home 后媒体时间基本不变；返回前台仍可恢复。
    func testActualBackgroundPolicyPausesAndResumes() {
        app.launchEnvironment["PLAYBACK_ALLOW_BACKGROUND"] = "0"
        start()
        XCUIDevice.shared.press(.home)
        pauseFor(6)
        app.activate()
        waitForControl("playing")
        XCTAssertLessThan(abs(backgroundDelta), 0.5)
    }

    /// 从系统控制中心发出暂停命令，返回 Demo 后实际媒体状态也应暂停。
    func testControlCenterPauseCommand() {
        start()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let screen = app.windows.firstMatch
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.01)).press(forDuration: 0.1, thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.65)))
        let pause = springboard.buttons.matching(NSPredicate(format: "label == 'Pause' OR label == '暂停' OR identifier == 'Pause' ")).firstMatch
        // 找不到系统控件即失败并保留层级，不退化为直接调用播放器方法。
        XCTAssertTrue(pause.waitForExistence(timeout: 5), springboard.debugDescription)
        pause.tap()
        app.activate()
        waitForControl("paused")
        let value = time
        pauseFor(1)
        XCTAssertEqual(time, value, accuracy: 0.2)
    }

    /// 启动原有 Demo 播放页，等到真实进度推进后再进行交互。
    private func start() {
        app.launch()
        XCTAssertTrue(app.staticTexts["playback.diagnostics"].waitForExistence(timeout: 10))
        waitForControl("playing")
        waitUntil("音频应实际推进") { self.time > 0.5 }
    }

    /// 标签字段为 控制状态|媒体秒数|bg=后台推进秒数。
    private var fields: [String] { return app.staticTexts["playback.diagnostics"].label.components(separatedBy: "|") }
    /// 媒体时间解析失败会保留负数，使断言失败，不把缺失标签当成零进度。
    private var time: Double { return fields.count > 1 ? Double(fields[1]) ?? -1 : -1 }
    /// 最近一次前后台往返的真实进度差。
    private var backgroundDelta: Double { return fields.count > 2 ? Double(fields[2].replacingOccurrences(of: "bg=", with: "")) ?? -999 : -999 }

    /// 等待 UI 显示与库一致的控制状态。
    private func waitForControl(_ value: String) {
        waitUntil("实际控制状态应为 \(value)") { self.fields.first == value }
    }

    /// 有界条件等待，失败时 XCTest 会保留具体用例和页面截图。
    private func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10), .completed, message)
    }

    /// 独立等待时间窗口，不阻塞被测 App 的主线程。
    private func pauseFor(_ seconds: TimeInterval) {
        let done = expectation(description: "等待系统时间窗口")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}
