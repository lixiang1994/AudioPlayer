//
//  AudioPlayerPhoneManager.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import Foundation
import AudioPlayer

class AudioPlayerPhoneManager: AudioPlayerManager {
    
    override init() {
        super.init()
        
        // 接收队列信息
        WatchSession.shared.receive(handle: { [weak self] (model: [Watch.Data.Item]) in
            guard let self = self else { return }
            let items = model.map({ item in
                AudioPlayerItem(item)
            })
            self.queue = .init(items)
            
        }, for: Watch.Identifier.Player.Queue)
        
        // 接收当前播放项信息
        WatchSession.shared.receive(handle: { [weak self] (model: Watch.Data.Item?) in
            guard let self = self else { return }
            if let model = model {
                let item = AudioPlayerItem(model)
                self.item = item
                self.switchable = (self.queue.prev(of: item), self.queue.next(of: item))
                
            } else {
                self.item = nil
                self.switchable = (false, false)
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
            self.state = state
            
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
            self.controlState = state
            
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
            self.loadingState = state
            
        }, for: Watch.Identifier.Player.LoadingState)
        
        // 接收当前系统音量
        WatchSession.shared.receive(handle: { [weak self] (value: Float) in
            guard let self = self else { return }
            self.volume = .init(value)
            
        }, for: Watch.Identifier.Player.Volume)
        
        // 接收当前播放倍速
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.rate = value
            
        }, for: Watch.Identifier.Player.Rate)
        
        // 接收当前缓冲进度
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.buffer = value
            
        }, for: Watch.Identifier.Player.Buffer)
        
        // 接收当前播放时间
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.current = value
            
        }, for: Watch.Identifier.Player.Current)
        
        // 接收当前总时长
        WatchSession.shared.receive(handle: { [weak self] (value: Double) in
            guard let self = self else { return }
            self.duration = value
            
        }, for: Watch.Identifier.Player.Duration)
        
        // 主动同步一次
        sync()
    }
    
    override func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
        WatchSession.shared.send(
            message: Watch.Data.Play(
                item: .init(item),
                queue: queue.items.map({ .init($0) })
            ),
            for: Watch.Identifier.Player.Play
        )
    }
    
    override func sync() {
        WatchSession.shared.send(for: Watch.Identifier.Player.Sync)
    }
    
    override func prev() {
        WatchSession.shared.send(for: Watch.Identifier.Player.Prev)
    }
    
    override func next() {
        WatchSession.shared.send(for: Watch.Identifier.Player.Next)
    }
    
    override func play() {
        WatchSession.shared.send(message: 0, for: Watch.Identifier.Player.ControlState)
    }
    
    override func pause() {
        WatchSession.shared.send(message: 1, for: Watch.Identifier.Player.ControlState)
    }
    
    override func set(rate: Double) {
        WatchSession.shared.send(message: rate, for: Watch.Identifier.Player.Rate)
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
