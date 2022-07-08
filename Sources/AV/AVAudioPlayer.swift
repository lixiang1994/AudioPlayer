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
    private(set) var url: URL?
    
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
        didSet { player.volume = .init(volume)}
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
    var isAutoPlay: Bool = true
    /// 允许后台播放
    var allowBackgroundPlayback: Bool = true
    
    var delegates: [AudioPlayerDelegateBridge<AnyObject>] = []
    private lazy var player = AVPlayer()
    
    private var playerTimeObserver: Any?
    private var userPaused: Bool = false
    private var isSeeking: Bool = false
    private var intendedToSeek: AudioPlayer.Seek?
    
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
        state = .failure(value)
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
        // 清空当前URL
        url = nil
        // 设置Seek状态
        isSeeking = false
    }
    
    private func addObserver() {
        removeObserver()
        // 当前播放时间 (间隔: 每秒10次)
        let interval = CMTime(value: 1, timescale: 10)
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] (time) in
            guard let self = self else { return }
            guard !self.isSeeking else { return }
            
            self.delegate{ $0.audioPlayer(self, updatedCurrent: CMTimeGetSeconds(time)) }
        }
        
        timeControlStatusObservation = player.observe(\.timeControlStatus) {
            [weak self] (observer, change) in
            guard let self = self else { return }
            guard case .playing = self.state else { return }
            
            switch observer.timeControlStatus {
            case .paused:
                self.control = .pausing
                self.userPaused = false
                
            case .playing:
                // 校准播放速率
                if observer.rate == .init(self.rate) {
                    self.control = .playing
                    self.userPaused = false
                    
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
                    let handle = {
                        self.state = .playing
                        
                        if self.isAutoPlay {
                            self.player.rate = .init(self.rate)
                            
                        } else {
                            self.player.pause()
                            self.userPaused = true
                        }
                    }
                    
                    // 查看是否有需要的Seek
                    if let seek = self.intendedToSeek {
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
        // 取消Seeks
        item.cancelPendingSeeks()
        // 设置Seek状态
        isSeeking = true
        // Seek到起始位置
        item.seek(to: .zero) { [weak self] (result) in
            guard let self = self else { return }
            // 设置Seek状态
            self.isSeeking = false
            // 判断循环模式
            if self.isLoop {
                // 继续播放
                self.player.rate = .init(self.rate)
                
            } else {
                // 暂停播放
                self.player.pause()
                self.userPaused = true
                // 设置完成状态
                self.state = .finished
            }
        }
    }
    
    /// 播放异常通知
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
        case .began?:
            if !userPaused, control == .playing { player.pause() }
        case .ended?:
            if !userPaused, control == .pausing { play() }
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
        if case .playing = state, !userPaused, control == .pausing {
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
            
        case .playing where !allowBackgroundPlayback:
            // 如果在播放阶段 不允许后台播放 则需要暂停
            guard !userPaused, control == .playing else { return }
            player.pause()
            
        default:
            break
        }
    }
}

extension AVAudioPlayer: AudioPlayerable {
    
    func prepare(url: AudioPlayerURLAsset) {
        // 清理原有资源
        clear()
        // 重置当前状态
        loading = .began
        state = .prepare
        
        // 设置当前URL
        self.url = url.value
        // 初始化播放器
        let asset: AVURLAsset
        if let temp = url as? AVURLAsset {
            asset = temp
            
        } else {
            asset = AVURLAsset(url: url.value)
        }
        
//        if asset.resourceLoader.delegate == nil {
//            asset.resourceLoader.setDelegate(AVAssetResourceLoader(), queue: .main)
//        }
        
        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        // 预缓冲时长 默认自动选择
        item.preferredForwardBufferDuration = 0
        // 控制倍速播放的质量: 音频质量最高，计算成本最高，适合音乐. 可变率从1/32到32;
        item.audioTimePitchAlgorithm = .spectral
        
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.rate = .init(rate)
        player.volume = .init(volume)
        player.isMuted = isMuted
        
        player.automaticallyWaitsToMinimizeStalling = false
        
        // 添加监听
        addObserver()
        addObserver(item: item)
    }
    
    func play() {
        switch state {
        case .playing where !isSeeking:
            player.rate = .init(rate)
            
        case .finished:
            state = .playing
            player.rate = .init(rate)
            
        default:
            break
        }
    }
    
    func pause() {
        guard case .playing = state, !isSeeking else { return }
        
        player.pause()
        userPaused = true
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
            intendedToSeek = target
            return
        }
        // 先取消上一个 保证Seek状态
        item.cancelPendingSeeks()
        // 设置Seek状态
        isSeeking = true
        // 代理回到
        delegate { $0.audioPlayer(self, seekBegan: target) }
        // 开始Seek
        seek(to: target, for: item) { [weak self] finished in
            guard let self = self else { return }
            // 设置Seek状态
            self.isSeeking = false
            // 代理回到
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
        let time = CMTimeGetSeconds(item.currentTime())
        return time.isNaN ? 0 : time
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
