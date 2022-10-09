//
//  AudioPlayerPhoneSource.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import Foundation
import AudioPlayer
import Combine

class AudioPlayerPhoneSource: AudioPlayerSource {
    
    private let manager: AudioPlayerManager
    
    private var subscriptions: [AnyCancellable] = []
    
    required init(_ manager: AudioPlayerManager) {
        self.manager = manager
        
        // 订阅List
        AudioPlayerPhoneList.shared.$items.sink { [weak self] items in
            guard let self = self else { return }
            self.manager.queue = .init(items)
            
        }.store(in: &subscriptions)
        
        // 接收当前播放项信息
        WatchSession.shared.receive(handle: { [weak self] (model: Watch.Data.Item) in
            guard let self = self else { return }
            if model.id.isEmpty {
                self.manager.item = nil
                self.manager.switchable = (false, false)
                
            } else {
                let item = AudioPlayerItem(model)
                self.manager.item = item
                self.manager.switchable = (self.manager.queue.prev(of: item), self.manager.queue.next(of: item))
            }
            
        }, for: Watch.Identifier.Player.Item)
        
        // 接收当前播放器状态
        WatchSession.shared.receive(handle: { [weak self] (value: Int) in
            guard let self = self else { return }
            let state: AudioPlayer.State
            switch value {
            case 0:  state = .prepare
            case 1:  state = .playing
            case 2:  state = .stopped
            case 3:  state = .finished
            case 4:  state = .failed(.none)
            default: return
            }
            self.manager.state = state
            
        }, for: Watch.Identifier.Player.State)
        
        // 接收当前播放器控制状态
        WatchSession.shared.receive(handle: { [weak self] (value: Int) in
            guard let self = self else { return }
            let state: AudioPlayer.ControlState
            switch value {
            case 0:  state = .playing
            case 1:  state = .pausing
            default: return
            }
            self.manager.controlState = state
            
        }, for: Watch.Identifier.Player.ControlState)
        
        // 接收当前播放器加载状态
        WatchSession.shared.receive(handle: { [weak self] (value: Int) in
            guard let self = self else { return }
            let state: AudioPlayer.LoadingState
            switch value {
            case 0:  state = .began
            case 1:  state = .ended
            default: return
            }
            self.manager.loadingState = state
            
        }, for: Watch.Identifier.Player.LoadingState)
        
        // 接收当前系统音量
        WatchSession.shared.receive(handle: { [weak self] (value: Float) in
            guard let self = self else { return }
            self.manager.volume = .init(value)
            
        }, for: Watch.Identifier.Player.Volume)
        
        // 接收当前播放倍速
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.manager.rate = value
            
        }, for: Watch.Identifier.Player.Rate)
        
        // 接收当前缓冲进度
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.manager.buffer = value
            
        }, for: Watch.Identifier.Player.Buffer)
        
        // 接收当前播放时间
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.manager.current = value
            
        }, for: Watch.Identifier.Player.Current)
        
        // 接收当前总时长
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.manager.duration = value
            
        }, for: Watch.Identifier.Player.Duration)
        
        // 主动发起同步
        sync()
    }
    
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
        WatchSession.shared.request(
            message: Watch.Data.Play(
                item: .init(item),
                queue: queue.items.map({ .init($0) })
            ),
            for: Watch.Identifier.Player.Play
        )
    }
    
    func sync() {
        WatchSession.shared.request(for: Watch.Identifier.Player.Sync)
    }
    
    func prev() {
        WatchSession.shared.request(for: Watch.Identifier.Player.Prev)
    }
    
    func next() {
        WatchSession.shared.request(for: Watch.Identifier.Player.Next)
    }
    
    func play() {
        WatchSession.shared.request(message: 0, for: Watch.Identifier.Player.ControlState)
    }
    
    func pause() {
        WatchSession.shared.request(message: 1, for: Watch.Identifier.Player.ControlState)
    }
    
    func set(rate: Double) {
        WatchSession.shared.request(message: rate, for: Watch.Identifier.Player.Rate)
    }
    
    deinit {
        // 暂停手机播放
        pause()
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
