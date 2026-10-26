import XCTest
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
    
    /// 用随机标识隔离 UserDefaults 播放记录，避免影响手工 Demo 数据。
    private func makeItem(_ url: URL) -> AudioPlayerItem {
        return .init(id: UUID().uuidString, title: "测试单集", cover: "", author: "测试", duration: 24, resource: url)
    }
}
