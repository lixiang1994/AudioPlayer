//
//  AudioPlayerDelegate.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import Foundation

public protocol AudioPlayerDelegate: AnyObject {
    /// 加载状态
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState)
    /// 控制状态
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState)
    /// 播放状态
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State)
    
    /// 更新缓冲进度
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double)
    /// 更新总时间 (秒)
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double)
    /// 更新当前时间 (秒)
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double)
    /// 跳转开始
    func audioPlayer(_ player: AudioPlayerable, seekBegan: AudioPlayer.Seek)
    /// 跳转结束
    func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek)
}

public extension AudioPlayerDelegate {
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) { }
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) { }
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) { }
    
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double) { }
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) { }
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) { }
    func audioPlayer(_ player: AudioPlayerable, seekBegan: AudioPlayer.Seek) { }
    func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek) { }
}
