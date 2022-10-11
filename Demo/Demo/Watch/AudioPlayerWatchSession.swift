//
//  AudioPlayerWatchSession.swift
//  Demo
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import AudioPlayer
import AVFAudio

class AudioPlayerWatchSession: WatchSession {
    
    static let shared = AudioPlayerWatchSession()
    
    private var lastSendCurrentTime: CFAbsoluteTime? = nil
    private var volumeObserver: Any?
    
    override init() {
        super.init()
        
        AudioPlayerManager.shared.add(delegate: self)
        AudioPlayerManager.shared.player.add(delegate: self)
        
        // 接收同步当前信息和状态的请求
        receive(handle: { [weak self] in
            guard let self = self else { return }
            let manager = AudioPlayerManager.shared
            self.audioPlayerManager(manager, changed: manager.queue)
            self.audioPlayerManager(manager, changed: manager.item)
            self.audioPlayerManager(manager, changed: manager.rate)
            self.audioPlayerManager(manager, changed: manager.mode)
            
            self.request(
                message: AVAudioSession.sharedInstance().outputVolume,
                for: Watch.Identifier.Player.Volume
            )
            
        }, for: Watch.Identifier.Player.Sync)
        
        // 接收播放请求
        receive(handle: { (value: Watch.Data.Play) in
            let queue = AudioPlayerQueue((value.queue.map({ .init($0) })))
            let item = AudioPlayerItem(value.item)
            
            if AudioPlayerManager.shared.item == item {
                AudioPlayerManager.shared.player.play()
                
            } else {
                AudioPlayerManager.shared.play(item, for: queue)
            }
            
        }, for: Watch.Identifier.Player.Play)
        
        // 接收播放控制状态
        receive(handle: { (state: Int) in
            switch state {
            case 0:
                AudioPlayerManager.shared.player.play()
                
            case 1:
                AudioPlayerManager.shared.player.pause()
                
            default:
                break
            }
            
        }, for: Watch.Identifier.Player.ControlState)
        
        // 接收播放上一首
        receive(handle: {
            AudioPlayerManager.shared.playPrev()
            
        }, for: Watch.Identifier.Player.Prev)
        
        // 接收播放下一首
        receive(handle: {
            AudioPlayerManager.shared.playNext()
            
        }, for: Watch.Identifier.Player.Next)
        
        // 接收倍速设置
        receive(handle: { (rate: Double) in
            let temp = (rate * 10).rounded() / 10
            AudioPlayerManager.shared.rate = .init(rawValue: temp) ?? ._1_0
            
        }, for: Watch.Identifier.Player.Rate)
        
        // 监听系统音量
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume) {
            [weak self] (session, _) in
            guard let self = self else { return }
            print("Output volume: \(session.outputVolume)")
            self.request(
                message: session.outputVolume,
                for: Watch.Identifier.Player.Volume
            )
        }
    }
}

extension AudioPlayerWatchSession: AudioPlayerManagerDelegate {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed queue: AudioPlayerQueue) {
        let items = queue.items.map({ item in
            Watch.Data.Item(item)
        })
        request(message: items, for: Watch.Identifier.Player.Queue)
    }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?) {
        let temp = item.map { item in
            Watch.Data.Item(item)
        } ?? .empty
        request(message: temp, for: Watch.Identifier.Player.Item)
        
        lastSendCurrentTime = nil
        
        // 同步播放器状态
        audioPlayerState(manager.player, state: manager.player.state)
        audioPlayerControlState(manager.player, state: manager.player.control)
        audioPlayerLoadingState(manager.player, state: manager.player.loading)
        audioPlayer(manager.player, updatedDuration: manager.player.duration)
        audioPlayer(manager.player, updatedCurrent: manager.player.current)
        audioPlayer(manager.player, updatedBuffer: manager.player.buffer)
    }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed rate: AudioPlayerManager.Rate) {
        request(message: rate.rawValue, for: Watch.Identifier.Player.Rate)
    }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed mode: AudioPlayerManager.PlaybackMode) {
        
    }
}

extension AudioPlayerWatchSession: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        let value: Int
        switch state {
        case .prepare:  value = 0
        case .playing:  value = 1
        case .stopped:  value = 2
        case .finished: value = 3
        case .failed:   value = 4
        }
        request(message: value, for: Watch.Identifier.Player.State)
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        let value: Int
        switch state {
        case .playing:  value = 0
        case .pausing:  value = 1
        }
        request(message: value, for: Watch.Identifier.Player.ControlState)
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        let value: Int
        switch state {
        case .began:  value = 0
        case .ended:  value = 1
        }
        request(message: value, for: Watch.Identifier.Player.LoadingState)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double) {
        request(message: progress, for: Watch.Identifier.Player.Buffer)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        // 控制发送间隔1秒一次 优化性能
        guard CFAbsoluteTimeGetCurrent() - (lastSendCurrentTime ?? 0) > 1 else {
            return
        }
        lastSendCurrentTime = CFAbsoluteTimeGetCurrent()
        request(message: time, for: Watch.Identifier.Player.Current)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        request(message: time, for: Watch.Identifier.Player.Duration)
    }
    
    func audioPlayer(_ player: AudioPlayerable, seekBegan: AudioPlayer.Seek) {
        // Seek前立刻发送当前时间 优化体验
        request(message: seekBegan.time, for: Watch.Identifier.Player.Current)
    }
}

extension Watch.Data.Item {
    
    init(_ item: AudioPlayerItem) {
        self.id = item.id
        self.title = item.title
        self.cover = item.cover
        self.author = item.author
        self.duration = item.duration
        self.resource = item.resource
    }
}

extension AudioPlayerItem {
    
    init(_ item: Watch.Data.Item) {
        self.id = item.id
        self.title = item.title
        self.cover = item.cover
        self.author = item.author
        self.duration = item.duration
        self.resource = item.resource
    }
}
