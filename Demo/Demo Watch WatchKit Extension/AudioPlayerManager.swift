//
//  AudioPlayerManager.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import AudioPlayer

protocol AudioPlayerSource {
    
    init(_ manager: AudioPlayerManager)
    
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue)
    
    func sync()
    
    func prev()
    func next()
    func play()
    func pause()
    
    func set(rate: Double)
}

class AudioPlayerManager: ObservableObject {
    
    static let shared = AudioPlayerManager()
    
    enum Source: Int {
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
    
    /// 状态
    @Published
    var state: AudioPlayer.State = .stopped
    @Published
    var controlState: AudioPlayer.ControlState = .pausing
    @Published
    var loadingState: AudioPlayer.LoadingState = .ended
    /// 倍速
    @Published
    var rate: Double = 1
    
    /// 音量
    @Published
    var volume: Double = 0
    
    /// 进度
    @Published
    var buffer: Double = 0
    @Published
    var progress: Double = 0
    @Published
    var current: Double = 0 {
        didSet {
            if duration > 0 {
                progress = current / duration
                
            } else {
                progress = 0
            }
        }
    }
    @Published
    var duration: Double = 0 {
        didSet {
            if duration > 0 {
                progress = current / duration
                
            } else {
                progress = 0
            }
        }
    }
    
    /// 来源
    @Published
    var source: Source = .phone
    private var __source: AudioPlayerSource?
    
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue, in source: Source) {
        switch source {
        case .phone where __source == nil || self.source != source:
            __source = AudioPlayerPhoneSource(self)
            
        case .watch where __source == nil || self.source != source:
            __source = AudioPlayerWatchSource(self)
            
        default:
            break
        }
        self.source = source
        __source?.play(item, for: queue)
    }
    
    func sync() {
        __source?.sync()
    }
    
    func prev() {
        __source?.prev()
    }
    
    func next() {
        __source?.next()
    }
    
    func play() {
        __source?.play()
    }
    
    func pause() {
        __source?.pause()
    }
    
    func set(rate: Double) {
        __source?.set(rate: rate)
    }
}
