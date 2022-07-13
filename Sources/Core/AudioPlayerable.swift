//
//  AudioPlayerable.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import Foundation

public protocol AudioPlayerURLAsset {
    var value: URL { get }
}

public protocol AudioPlayerable: NSObjectProtocol {
    
    /// 准备
    func prepare(resource: AudioPlayerURLAsset)
    /// 播放 
    func play()
    /// 暂停
    func pause()
    /// 停止
    func stop()
    /// 快速定位到指定播放时间点 (多次调用 以最后一次为准)
    func seek(to target: AudioPlayer.Seek)
    
    /// 资源
    var resource: AudioPlayerURLAsset? { get }
    /// 播放器当前状态
    var state: AudioPlayer.State { get }
    /// 播放器控制状态
    var control: AudioPlayer.ControlState { get }
    /// 播放器加载状态
    var loading: AudioPlayer.LoadingState { get }
    
    /// 当前时间
    var current: TimeInterval { get }
    /// 视频总时长
    var duration: TimeInterval { get }
    /// 缓冲进度 0 - 1
    var buffer: Double { get }
    
    /// 播放速率
    var rate: Double { get set }
    /// 是否静音
    var isMuted: Bool { get set }
    /// 音量控制
    var volume: Double { get set }
    /// 是否循环播放  默认: false
    var isLoop: Bool { get set }
    /// 是否自动播放  默认: true
    var isAutoplay: Bool { get set }
    /// 允许后台播放 默认: true
    var allowBackgroundPlayback: Bool { get set }
    
    /// 添加委托
    func add(delegate: AudioPlayerDelegate)
    /// 移除委托
    func remove(delegate: AudioPlayerDelegate)
}

extension URL: AudioPlayerURLAsset {
    
    public var value: URL {
        return self
    }
}
