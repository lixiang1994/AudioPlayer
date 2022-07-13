//
//  AVAudioPlayer.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import UIKit
import AVFoundation

public extension AudioPlayer {
    
    static let av: Builder = .init { AVAudioPlayer() }
}

class AVAudioPlayer: NSObject {
        
    static let shared = AVAudioPlayer()
    
    /// 当前URL
    private(set) var resource: AudioPlayerURLAsset?
    
    /// 播放状态
    private (set) var state: AudioPlayer.State = .stopped {
        didSet {
            delegate { $0.audioPlayerState(self, state: state) }
        }
    }
    
    /// 控制状态
    private(set) var control: AudioPlayer.ControlState = .pausing {
        didSet {
            delegate { $0.audioPlayerControlState(self, state: control) }
        }
    }
    
    /// 加载状态
    private(set) var loading: AudioPlayer.LoadingState = .ended {
        didSet {
            delegate { $0.audioPlayerLoadingState(self, state: loading) }
        }
    }
    
    /// 播放速率 0.5 - 2.0
    var rate: Double = 1.0 {
        didSet {
            guard case .playing = state, case .playing = control else { return }
            player.rate = .init(rate)
        }
    }
    /// 音量 0 - 1
    var volume: Double = 1.0 {
        didSet {
            player.volume = .init(volume)
        }
    }
    /// 是否静音
    var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
        }
    }
    /// 是否循环播放
    var isLoop: Bool = false
    /// 是否自动播放
    var isAutoplay: Bool = true
    /// 允许后台播放
    var allowBackgroundPlayback: Bool = true
    
    var delegates: [AudioPlayerDelegateBridge<AnyObject>] = []
    
    private lazy var player = AVPlayer()
    
    private var playerTimeObserver: Any?
    
    /// 是否想要跳转 当非playing状态时 如果调用了seek(to:)  记录状态 在playing时设置跳转
    private var intendedToSeek: AudioPlayer.Seek?
    /// 是否想要播放 当seeking时如果调用了play() 或者 pasue() 记录状态 在seeking结束时设置对应状态
    private var intendedToPlay: Bool = false
    
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var reasonForWaitingToPlayObservation: NSKeyValueObservation?
    
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemDurationObservation: NSKeyValueObservation?
    private var itemLoadedTimeRangesObservation: NSKeyValueObservation?
    private var itemPlaybackLikelyToKeepUpObservation: NSKeyValueObservation?
    
    /// 后台任务标识
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    override init() {
        super.init()
        
        setup()
        setupNotification()
    }
    
    private func setup() {
        rate = 1.0
        volume = 1.0
        isMuted = false
        isLoop = false
    }
    
    private func setupNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemPlaybackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemFailedToPlayToEndTime),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
}

extension AVAudioPlayer {
    
    /// 错误
    private func error(_ value: Swift.Error?) {
        clear()
        state = .failed(value)
    }

    /// 清理
    private func clear() {
        guard let item = player.currentItem else { return }
        
        loading = .ended
        
        player.pause()
        
        // 取消相关
        item.cancelPendingSeeks()
        item.asset.cancelLoading()
        
        // 移除监听
        removeObserver()
        removeObserver(item: item)
        
        // 移除item
        player.replaceCurrentItem(with: nil)
        // 清空资源
        resource = nil
        // 清理意图
        intendedToSeek = nil
        intendedToPlay = false
    }
    
    private func addObserver() {
        removeObserver()
        // 当前播放时间 (间隔: 每秒10次)
        let interval = CMTime(value: 1, timescale: 10)
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] (time) in
            guard let self = self else { return }
            guard case .playing = self.state else { return }
            
            if let seek = self.intendedToSeek {
                self.delegate{ $0.audioPlayer(self, updatedCurrent: seek.time) }
                
            } else {
                self.delegate{ $0.audioPlayer(self, updatedCurrent: CMTimeGetSeconds(time)) }
            }
        }
        
        timeControlStatusObservation = player.observe(\.timeControlStatus) {
            [weak self] (observer, change) in
            guard let self = self else { return }
            guard case .playing = self.state else { return }
            
            switch observer.timeControlStatus {
            case .paused:
                self.control = .pausing
                
            case .playing:
                // 校准播放速率
                if observer.rate == .init(self.rate) {
                    self.control = .playing
                    
                } else {
                    observer.rate = .init(self.rate)
                }
                
            default:
                break
            }
        }
        
        reasonForWaitingToPlayObservation = player.observe(\.reasonForWaitingToPlay) {
            [weak self] (observer, change) in
            guard let self = self else { return }
            guard observer.automaticallyWaitsToMinimizeStalling else { return }
            guard observer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            
            switch observer.reasonForWaitingToPlay {
            case .toMinimizeStalls?:
                print("toMinimizeStalls")
                self.loading = .began
                
            case .evaluatingBufferingRate?:
                print("evaluatingBufferingRate")
                
            case .noItemToPlay?:
                print("noItemToPlay")
                
            default:
                self.loading = .ended
            }
        }
    }
    private func removeObserver() {
        if let observer = playerTimeObserver {
            playerTimeObserver = nil
            player.removeTimeObserver(observer)
        }
        
        if let observer = timeControlStatusObservation {
            observer.invalidate()
            timeControlStatusObservation = nil
        }
        
        if let observer = reasonForWaitingToPlayObservation {
            observer.invalidate()
            reasonForWaitingToPlayObservation = nil
        }
    }
    
    private func addObserver(item: AVPlayerItem) {
        do {
            let observation = item.observe(\.status) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                switch observer.status {
                case .readyToPlay:
                    let handle = { [weak self] in
                        guard let self = self else { return }
                        self.intendedToSeek = nil
                        self.state = .playing
                        
                        if self.intendedToPlay {
                            self.play()
                            
                        } else {
                            self.pause()
                        }
                    }
                    
                    // 查看是否有需要的Seek
                    if let seek = self.intendedToSeek {
                        self.player.pause()
                        self.seek(to: seek, for: item) { _ in
                            handle()
                        }
                        
                    } else {
                        handle()
                    }
                    
                    self.itemStatusObservation = nil
                    
                case .failed:
                    self.error(item.error)
                    
                default:
                    break
                }
            }
            itemStatusObservation = observation
        }
        do {
            let observation = item.observe(\.duration) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                self.delegate { $0.audioPlayer(self, updatedDuration: observer.duration.seconds) }
            }
            itemDurationObservation = observation
        }
        do {
            let observation = item.observe(\.loadedTimeRanges) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                self.delegate { $0.audioPlayer(self, updatedBuffer: self.buffer) }
            }
            itemLoadedTimeRangesObservation = observation
        }
        do {
            let observation = item.observe(\.isPlaybackLikelyToKeepUp) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                self.loading = !observer.isPlaybackLikelyToKeepUp ? .began : .ended
            }
            itemPlaybackLikelyToKeepUpObservation = observation
        }
    }
    private func removeObserver(item: AVPlayerItem) {
        itemStatusObservation = nil
        itemDurationObservation = nil
        itemLoadedTimeRangesObservation = nil
        itemPlaybackLikelyToKeepUpObservation = nil
    }
}

extension AVAudioPlayer {
    
    /// 播放结束通知
    @objc
    private func itemDidPlayToEndTime(_ notification: NSNotification) {
        guard let item = notification.object as? AVPlayerItem, item == player.currentItem else {
            return
        }
        // 判断是否循环播放
        if isLoop {
            // Seek到起始位置
            seek(to: .init(time: .zero))
            
        } else {
            // 暂停播放
            pause()
            // 设置完成状态
            state = .finished
        }
    }
    
    /// 播放中断通知
    @objc
    private func itemPlaybackStalled(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        guard case .playing = state else {
            return
        }
        play()
    }
    
    /// 播放失败通知
    @objc
    private func itemFailedToPlayToEndTime(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        self.error(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
    }
    
    /// 会话线路变更通知
    @objc
    private func sessionRouteChange(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let reason = info[AVAudioSessionRouteChangeReasonKey] as? Int else {
            return
        }
        guard let _ = player.currentItem else { return }
        
        switch AVAudioSession.RouteChangeReason(rawValue: UInt(reason)) {
        case .oldDeviceUnavailable?:
            DispatchQueue.main.async {
                self.player.pause()
            }
        default: break
        }
    }
    
    /// 会话中断通知
    @objc
    private func sessionInterruption(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let type = info[AVAudioSessionInterruptionTypeKey] as? Int else {
            return
        }
        guard let _ = player.currentItem else { return }
        
        switch AVAudioSession.InterruptionType(rawValue: .init(type)) {
        case .began? where intendedToPlay:
            player.pause()
            
        case .ended? where intendedToPlay:
            play()
            
        default:
            break
        }
    }
    
    @objc
    private func willEnterForeground(_ notification: NSNotification) {
        guard player.currentItem != .none else { return }
        
        // 结束后台任务
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
        
        // 继续播放
        if case .playing = state, intendedToPlay {
            play()
        }
    }
    
    @objc
    private func didEnterBackground(_ notification: NSNotification) {
        guard player.currentItem != .none else { return }
        
        switch state {
        case .prepare where allowBackgroundPlayback:
            // 如果在准备阶段 则开启后台任务 防止被挂起
            backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
                guard let self = self else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
                self.backgroundTaskIdentifier = .invalid
            }
            
        case .playing where !allowBackgroundPlayback && intendedToPlay:
            // 如果在播放阶段 不允许后台播放 则需要暂停
            player.pause()
            
        default:
            break
        }
    }
}

extension AVAudioPlayer: AudioPlayerable {
    
    func prepare(resource: AudioPlayerURLAsset) {
        // 清理原有资源
        clear()
        // 重置当前状态
        loading = .began
        state = .prepare
        
        // 设置当前资源
        self.resource = resource
        
        let asset: AVURLAsset
        if let temp = resource as? AVURLAsset {
            asset = temp
            
        } else {
            asset = AVURLAsset(url: resource.value)
        }
        
//        if asset.resourceLoader.delegate == nil {
//            asset.resourceLoader.setDelegate(AVAssetResourceLoader(), queue: .main)
//        }
        
        // 初始化播放项
        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        // 预缓冲时长 默认自动选择
        item.preferredForwardBufferDuration = 0
        // 控制倍速播放的质量: 音频质量最高，计算成本最高，适合音乐. 可变率从1/32到32;
        item.audioTimePitchAlgorithm = .spectral
        
        // 初始化播放器
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.rate = .init(rate)
        player.volume = .init(volume)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = false
        
        // 添加监听
        addObserver()
        addObserver(item: item)
        
        intendedToPlay = isAutoplay
    }
    
    func play() {
        switch state {
        case .prepare:
            intendedToPlay = true
            
        case .playing:
            intendedToPlay = true
            player.rate = .init(rate)
            
        case .finished:
            state = .playing
            intendedToPlay = true
            // Seek到起始位置
            seek(to: .init(time: .zero))
            
        default:
            break
        }
    }
    
    func pause() {
        intendedToPlay = false
        player.pause()
    }
    
    func stop() {
        clear()
        state = .stopped
    }
    
    func seek(to target: AudioPlayer.Seek) {
        guard
            let item = player.currentItem,
            player.status == .readyToPlay,
            case .playing = state else {
            // 设置跳转意图
            intendedToSeek = target
            return
        }
        // 先取消上一个 保证Seek状态
        item.cancelPendingSeeks()
        // 设置跳转意图
        intendedToSeek = target
        // 暂停当前播放
        player.pause()
        // 代理回调
        delegate { $0.audioPlayer(self, seekBegan: target) }
        // 开始Seek
        seek(to: target, for: item) { [weak self] finished in
            guard let self = self else { return }
            // 清空跳转意图
            self.intendedToSeek = nil
            // 根据播放意图继续播放
            if finished, self.intendedToPlay {
                self.play()
            }
            // 代理回调
            self.delegate { $0.audioPlayer(self, seekEnded: target) }
        }
    }
    
    private func seek(to target: AudioPlayer.Seek, for item: AVPlayerItem, with completion: @escaping ((Bool) -> Void)) {
        var time = CMTime(
            seconds: target.time,
            preferredTimescale: item.duration.timescale
        )
        // 校验目标时间是否可跳转
        let isSeekable = item.seekableTimeRanges.contains { value in
            value.timeRangeValue.containsTime(time)
        }
        if !isSeekable {
            // 限制跳转时间
            time = min(max(time, .zero), item.duration)
        }
        item.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { (finished) in
            // 完成回调
            target.completion?(finished)
            completion(finished)
        }
    }
    
    var current: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        if let seek = intendedToSeek {
            return seek.time
            
        } else {
            let time = CMTimeGetSeconds(item.currentTime())
            return time.isNaN ? 0 : time
        }
    }
    
    var duration: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let time = CMTimeGetSeconds(item.duration)
        return time.isNaN ? 0 : time
    }
    
    var buffer: Double {
        guard let item = player.currentItem else { return 0 }
        guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        guard duration > 0 else { return 0 }
        let buffer = range.start.seconds + range.duration.seconds
        return buffer / duration
    }
}

extension AVAudioPlayer: AudioPlayerDelegates {
    
    typealias Element = AudioPlayerDelegate
}

fileprivate extension AVPlayerItem {
    
    func setAudioTrack(_ isEnabled: Bool) {
        tracks.filter { $0.assetTrack?.mediaType == .some(.audio) }.forEach { $0.isEnabled = isEnabled }
    }
}

extension AVURLAsset: AudioPlayerURLAsset {
    
    public var value: URL {
        return url
    }
}

fileprivate func min(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    return CMTimeCompare(lhs, rhs) == -1 ? lhs : rhs
}

fileprivate func max(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    return CMTimeCompare(lhs, rhs) == 1 ? lhs : rhs
}
