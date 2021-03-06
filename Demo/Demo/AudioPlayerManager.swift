//
//  AudioPlayerManager.swift
//  Demo
//
//  Created by 李响 on 2022/7/9.
//

import AudioPlayer
import AVFoundation

protocol AudioPlayerManagerDelegate: AnyObject {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed mode: AudioPlayerManager.PlaybackMode)
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?)
}

extension AudioPlayerManagerDelegate {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed mode: AudioPlayerManager.PlaybackMode) { }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?) { }
}

class AudioPlayerManager: NSObject {
    
    static let shared = AudioPlayerManager()
     
    /// 播放器
    let player = AudioPlayer.av.instance()
    /// 播放模式 默认顺序播放
    var mode: PlaybackMode = .sequential {
        didSet {
            player.isLoop = mode == .single
            delegate { $0.audioPlayerManager(self, changed: mode) }
        }
    }
    /// 播放项队列
    private(set) var queue: AudioPlayerQueue = .init([])
    /// 当前播放项
    private(set) var item: AudioPlayerItem?
    /// 可切换状态 (prev: 上一首, next: 下一首)
    private(set) var switchable: (prev: Bool, next: Bool) = (false, false)
    
    private lazy var remote = RemoteControl(player)
    
    var delegates: [AudioPlayerDelegateBridge<AnyObject>] = []
    
    private var lastUpdateItemStateTime: TimeInterval = 0
    
    override init() {
        super.init()
        setup()
        setupNotification()
    }
    
    /// 播放队列的项目
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
        // 更新当前队列
        self.queue = queue
        // 更新当前Item
        update(item)
    }
    
    /// 播放上一项
    func playPrev() {
        guard let item = item else { return }
        guard let temp = queue.prev(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    /// 播放下一项
    func playNext() {
        guard let item = item else { return }
        guard let temp = queue.next(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    /// 重播当前项
    func replay() {
        guard let item = item else { return }
        update(item)
    }
}

extension AudioPlayerManager {
    
    private func setup() {
        // 设置播放倍速
        player.rate = 1.0
        // 允许后台播放
        player.allowedBackgroundPlayback = true
        // 添加播放器代理
        player.add(delegate: self)
        
        // 设置远程控制 (上一首/下一首) 的回调
        remote.playPrev = { [weak self] in
            self?.playPrev()
        }
        remote.playNext = { [weak self] in
            self?.playNext()
        }
    }
    
    private func setupNotification() {
        /// 会话线路变更通知
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            guard
                let info = sender.userInfo,
                let reason = info[AVAudioSessionRouteChangeReasonKey] as? Int else {
                return
            }
            switch AVAudioSession.RouteChangeReason(rawValue: UInt(reason)) {
            case .oldDeviceUnavailable?:
                DispatchQueue.main.async {
                    // 暂停播放
                    self.player.pause()
                }
                
            default: break
            }
        }
        /// 应用即将终止通知
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            // 应用终止时 存储Item状态
            self.updateItemState()
        }
    }
}

extension AudioPlayerManager {
    
    private func update(_ item: AudioPlayerItem?) {
        // 置空当前Item, 防止状态被错误更新
        self.item = nil
        
        if let item = item {
            // 准备播放资源
            player.prepare(resource: item.resource)
            // 处理Item状态
            if let state = item.state {
                switch state {
                case .record(let time):
                    // 自动跳转到上一次播放的进度
                    player.seek(to: .init(time: time))
                    
                default:
                    break
                }
            }
            // 设置可切换状态
            switchable = (queue.prev(of: item), queue.next(of: item))
            
            // 设置远程控制
            remote.set(
                title: item.title,
                artist: item.author,
                thumb: UIImage(named: item.cover)!,
                url: item.resource
            )
            remote.set(switchable: switchable)
            
            // 设置当前Item
            self.item = item
        }
        
        delegate { $0.audioPlayerManager(self, changed: item) }
    }
    
    private func updateItemState() {
        switch player.state {
        case .playing:
            item?.state = .record(player.current)
            
        case .finished:
            item?.state = .played
            
        case .failed where item?.state == nil:
            item?.state = .failed
            
        default:
            break
        }
    }
    
    private func playRandom() {
        guard let item = item else { return }
        update(queue.random(of: item))
    }
}

extension AudioPlayerManager: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        
        updateItemState()
        
        switch state {
        case .prepare:
            // 准备阶段
            
            // 设置音频会话模式
            UIApplication.shared.beginReceivingRemoteControlEvents()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话创建失败")
            }
            
        case .playing:
            // 播放阶段
            break
            
        case .stopped:
            // 停止阶段
            
            // 设置音频会话模式
            UIApplication.shared.endReceivingRemoteControlEvents()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话释放失败")
            }
            
        case .finished:
            // 完成阶段
            
            // 根据播放模式设置
            switch mode {
            case .random:
                // 播放随机项
                playRandom()
                
            case .sequential:
                // 播放下一首
                playNext()
                
            default:
                break
            }
            
        case .failed(let error):
            // 失败阶段
            print(error?.localizedDescription ?? "")
        }
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        updateItemState()
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        updateItemState()
    }
    
    func audioPlayer(_ player: AudioPlayerable, seekBegan: AudioPlayer.Seek) {
        updateItemState()
    }
    
    func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek) {
        updateItemState()
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        // 控制一秒间隔更新一次状态
        guard (lastUpdateItemStateTime - time).magnitude > 1 else {
            return
        }
        lastUpdateItemStateTime = time
        updateItemState()
    }
}

extension AudioPlayerManager: AudioPlayerDelegates {
    
    typealias Element = AudioPlayerManagerDelegate
}

extension AudioPlayerManager {
    
    enum PlaybackMode {
        // 单曲循环
        case single
        // 随机播放
        case random
        // 顺序播放
        case sequential
    }
}
