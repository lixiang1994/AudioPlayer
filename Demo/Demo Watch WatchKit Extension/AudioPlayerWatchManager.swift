//
//  AudioPlayerWatchManager.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import UIKit
import AudioPlayer
import AVFAudio
import MediaPlayer.MPNowPlayingInfoCenter
import MediaPlayer.MPRemoteCommandCenter

class AudioPlayerWatchManager: AudioPlayerManager {
    
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
    
    override init() {
        super.init()
        rate = lastRate
        // 设置播放倍速
        player.rate = rate
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
            self.volume = .init(session.outputVolume)
        }
        
        queue = AudioPlayerQueue(
            [
                .init(
                    id: "1",
                    title: "最伟大的作品",
                    cover: "cover_01",
                    author: "周杰伦",
                    duration: 880.85,
                    resource: URL(string: "https://chtbl.com/track/1F1B1F/traffic.megaphone.fm/WSJ2560705456.mp3")!
                ),
//                .init(
//                    id: "2",
//                    title: "布拉格广场",
//                    cover: "cover_02",
//                    author: "蔡依林,周杰伦",
//                    duration: 293.90,
//                    resource: Bundle.main.url(forResource: "蔡依林,周杰伦 - 布拉格广场", withExtension: "mp3")!
//                ),
                .init(
                    id: "3",
                    title: "Test",
                    cover: "cover_02",
                    author: "lee",
                    duration: 2021.52,
                    resource: URL(string: "https://dts.podtrac.com/redirect.mp3/chrt.fm/track/8DB4DB/pdst.fm/e/nyt.simplecastaudio.com/03d8b493-87fc-4bd1-931f-8a8e9b945d8a/episodes/66076fed-8026-4682-b0d0-a31f72cffb3c/audio/128/default.mp3?aid=rss_feed&awCollectionId=03d8b493-87fc-4bd1-931f-8a8e9b945d8a&awEpisodeId=66076fed-8026-4682-b0d0-a31f72cffb3c&feed=54nAGcIl")!
                )
            ]
        )
    }
    
    override func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
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
                    self.queue = queue
                    self.update(item)
                }
            }
            
        } catch {
            print("音频会话创建失败")
        }
    }
    
    override func sync() {
        state = player.state
        controlState = player.control
        loadingState = player.loading
        buffer = player.buffer
        current = player.current
        duration = player.duration
    }
    
    override func prev() {
        guard let item = item else { return }
        guard let temp = queue.prev(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    override func next() {
        guard let item = item else { return }
        guard let temp = queue.next(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    override func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            // 尝试激活会话, 激活完成后开始播放
            // ⚠️ 已知BUG, 当设备选择页面打开时如果息屏 再次回到APP后页面会消失且无法再次调起, 除非重启APP
            session.activate { [weak self] (result, error) in
                guard let self = self else { return }
                guard error == nil else { return }
                DispatchQueue.main.async {
                    self.player.play()
                }
            }
            
        } catch {
            print("音频会话创建失败")
        }
    }
    
    override func pause() {
        player.pause()
    }
    
    override func set(rate: Double) {
        self.rate = rate
        lastRate = rate
        player.rate = rate
    }
}

extension AudioPlayerWatchManager {
    
    private func update(_ item: AudioPlayerItem?) {
        // 设置当前Item
        self.item = item
        
        if let item = item {
            // 准备播放资源
            player.prepare(resource: item.resource)
            // 设置可切换状态
            switchable = (queue.prev(of: item), queue.next(of: item))
            
            // 设置远程控制
            remote.set(
                title: item.title,
                artist: item.author,
                url: item.resource
            )
            remote.set(switchable: switchable)
            
        } else {
            // 播放器停止
            player.stop()
            // 设置可切换状态
            switchable = (false, false)
        }
    }
}

extension AudioPlayerWatchManager: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        self.state = state
        
        switch state {
        case .prepare:
            // 准备阶段
            break
            
        case .playing:
            // 播放阶段
            break
            
        case .stopped:
            // 停止阶段
            break
            
        case .finished:
            // 完成阶段
            // 播放下一首
            next()
            
        case .failed(let error):
            // 失败阶段
            print(error?.localizedDescription ?? "")
        }
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        self.controlState = state
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        self.loadingState = state
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double) {
        self.buffer = progress
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        self.current = time
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        self.duration = time
    }
}

extension AudioPlayerWatchManager {
 
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
