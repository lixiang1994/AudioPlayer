//
//  AudioPlayerManager.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import AudioPlayer

class AudioPlayerManager: NSObject, ObservableObject {
    
    static let shared = AudioPlayerWatchManager()
    
    enum Source {
    case phone
    case watch
    }
    
    /// 播放项队列
    @Published
    var queue: AudioPlayerQueue = .init([])
    /// 当前播放项
    @Published
    var item: AudioPlayerItem?
    /// 可切换状态 (prev: 上一首, next: 下一首)
    @Published
    var switchable: (prev: Bool, next: Bool) = (false, false)
    
    @Published
    var state: AudioPlayer.State = .stopped
    @Published
    var controlState: AudioPlayer.ControlState = .pausing
    @Published
    var loadingState: AudioPlayer.LoadingState = .ended
    @Published
    var rate: Double = 1
    
    @Published
    var volume: Double = 0
    
    @Published
    var buffer: Double = 0
    @Published
    var progress: Double = 0
    @Published
    var current: Double = 0 {
        didSet {
            guard duration > 0 else { return }
            progress = current / duration
        }
    }
    @Published
    var duration: Double = 0 {
        didSet {
            guard duration > 0 else { return }
            progress = current / duration
        }
    }
    
    @Published
    var source: Source = .phone
    
    /// 播放队列的项目
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
        
    }
    
    func sync() {
    }
    
    func prev() {
    }
    
    func next() {
    }
    
    func play() {
    }
    
    func pause() {
    }
    
    func set(rate: Double) {
        self.rate = rate
    }
}
