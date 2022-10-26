//
//  AudioPlayerWatchSource.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import UIKit
import AudioPlayer
import AVFAudio
import MediaPlayer.MPNowPlayingInfoCenter
import MediaPlayer.MPRemoteCommandCenter
import Combine

class AudioPlayerWatchSource: NSObject, AudioPlayerSource {
    
    /// 播放器
    private let player = AudioPlayer.av.instance()
    /// 远程控制
    private lazy var remote = RemoteControl(player)
    
    private var volumeObserver: Any?
    
    /// 上一次倍速
    private var lastRate: Double {
        get { UserDefaults.standard.value(forKey: "com.watch.audio.player.rate") as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: "com.watch.audio.player.rate") }
    }
    
    private let manager: AudioPlayerManager
    
    private var subscriptions: [AnyCancellable] = []
    
    required init(_ manager: AudioPlayerManager) {
        self.manager = manager
        super.init()
        // 订阅List
        AudioPlayerWatchList.shared.$items.sink { [weak self] items in
            guard let self = self else { return }
            self.manager.queue = .init(items)
            // 如果新队列中不包含当前播放的项 则清空
            if let item = self.manager.item, !self.manager.queue.contains(item) {
                self.update(nil)
            }
            
        }.store(in: &subscriptions)
        
        // 设置播放倍速
        manager.rate = lastRate
        player.rate = lastRate
        // 添加播放器代理
        player.add(delegate: self)
        
        // 设置远程控制 (上一首/下一首) 的回调
        remote.playPrev = { [weak self] in
            self?.prev()
        }
        remote.playNext = { [weak self] in
            self?.next()
        }
        
        // 设置音量监听
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume) {
            [weak self] (session, _) in
            guard let self = self else { return }
            print("Output volume: \(session.outputVolume)")
            self.manager.volume = .init(session.outputVolume)
        }
    }
    
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
        // 设置音频会话模式
        // https://developer.apple.com/documentation/watchkit/storyboard_support/playing_background_audio
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            // 尝试激活会话, 激活完成后设置队列和播放项
            // ⚠️ 已知BUG, 当设备选择页面打开时如果息屏 再次回到APP后页面会消失且无法再次调起, 除非重启APP
            session.activate { [weak self] (result, error) in
                guard let self = self else { return }
                guard error == nil else { return }
                DispatchQueue.main.async {
                    self.manager.queue = queue
                    self.update(item)
                }
            }
            
        } catch {
            print("音频会话创建失败")
        }
    }
    
    func sync() {
        manager.state = player.state
        manager.controlState = player.control
        manager.loadingState = player.loading
        manager.buffer = player.buffer
        manager.current = player.current
        manager.duration = player.duration
    }
    
    func prev() {
        guard let item = manager.item else { return }
        guard let temp = manager.queue.prev(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    func next() {
        guard let item = manager.item else { return }
        guard let temp = manager.queue.next(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            // 尝试激活会话, 激活完成后开始播放
            // ⚠️ 已知BUG, 当设备选择页面打开时如果息屏 再次回到APP后页面会消失且无法再次调起, 除非重启APP
            session.activate { [weak self] (result, error) in
                guard let self = self else { return }
                guard error == nil else { return }
                DispatchQueue.main.async {
                    switch self.player.state {
                    case .failed:
                        // 失败状态时点击播放按钮 调用重播
                        self.replay()
                        
                    default:
                        // 开始播放
                        self.player.play()
                    }
                }
            }
            
        } catch {
            print("音频会话创建失败")
        }
    }
    
    func pause() {
        player.pause()
    }
    
    func replay() {
        guard let item = manager.item else { return }
        update(item)
    }
    
    func set(rate: Double) {
        manager.rate = rate
        player.rate = rate
        lastRate = rate
    }
}

extension AudioPlayerWatchSource {
    
    private func update(_ item: AudioPlayerItem?) {
        // 设置当前Item
        manager.item = item
        
        if let item = item {
            // 准备播放资源
            // 优先播放本地资源 如果本地没有则播放网络资源
            if let url = AudioFiles.url(for: item.id) {
                player.prepare(resource: url)
                
            } else {
                player.prepare(resource: item.resource)
            }
            // 设置可切换状态
            manager.switchable = (manager.queue.prev(of: item), manager.queue.next(of: item))
            
            // 设置远程控制
            remote.set(
                title: item.title,
                artist: item.author,
                url: item.resource
            )
            remote.set(switchable: manager.switchable)
            
        } else {
            // 播放器停止
            player.stop()
            // 设置可切换状态
            manager.switchable = (false, false)
        }
    }
}

extension AudioPlayerWatchSource: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        manager.state = state
        
        switch state {
        case .prepare:
            // 准备阶段
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
            
        case .playing:
            // 播放阶段
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
            
        case .stopped:
            // 停止阶段
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
            
        case .finished:
            // 完成阶段
            // 播放下一首
            next()
            
        case .failed:
            // 失败阶段
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
        }
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        manager.controlState = state
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        manager.loadingState = state
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double) {
        manager.buffer = progress
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        manager.current = time
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        manager.duration = time
    }
}

extension AudioPlayerWatchSource {
 
    class RemoteControl: AudioPlayerRemoteControl {
        
        var playPrev: (()-> Void)?
        var playNext: (()-> Void)?
        
        override func setupCommand() {
            super.setupCommand()
            
            // 添加上一首/下一首命令
            let remote = MPRemoteCommandCenter.shared()
            remote.previousTrackCommand.addTarget(self, action: #selector(prevCommandAction))
            remote.nextTrackCommand.addTarget(self, action: #selector(nextCommandAction))
        }
        
        override func cleanCommand() {
            super.cleanCommand()
            // 移除命令
            let remote = MPRemoteCommandCenter.shared()
            remote.previousTrackCommand.removeTarget(self)
            remote.nextTrackCommand.removeTarget(self)
        }
        
        @objc
        private func prevCommandAction(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
            playPrev?()
            return .success
        }
        
        @objc
        private func nextCommandAction(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
            playNext?()
            return .success
        }
        
        /// 设置切换状态
        /// - Parameter state: (上一首, 下一首)
        func set(switchable state: (Bool, Bool)) {
            let remote = MPRemoteCommandCenter.shared()
            remote.previousTrackCommand.isEnabled = state.0
            remote.nextTrackCommand.isEnabled = state.1
        }
    }
}
