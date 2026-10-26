//
//  AudioPlayerRemoteControl.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import UIKit
import MediaPlayer.MPNowPlayingInfoCenter
import MediaPlayer.MPRemoteCommandCenter

open class AudioPlayerRemoteControl: NSObject {
    
    public let player: AudioPlayerable
    
    /// 上次同步的媒体时间，用于纠正 seek；正常播放由系统自行推算进度。
    private var lastReportedTime: TimeInterval = 0
    /// 上次同步的用户倍速，用于在没有控制状态变化时发现倍速设置变更。
    private var lastReportedRate: Double = 1

    public init(_ player: AudioPlayerable) {
        self.player = player
        super.init()
        // 添加播放器代理
        player.add(delegate: self)
        
        setupCommand()
    }
    
    /// 设置远程控制
    open func setupCommand() {
        cleanCommand()
        
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.addTarget(self, action: #selector(playCommandAction))
        remote.pauseCommand.addTarget(self, action: #selector(pauseCommandAction))
        
        updatePlayingInfo()
    }
    
    /// 清理远程控制
    open func cleanCommand() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.removeTarget(self)
        remote.pauseCommand.removeTarget(self)
    }
    
    /// 更新播放信息
    public func updatePlayingInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyPlaybackDuration] = player.duration
        // 用户选择的倍速和当前实际播放速率含义不同，暂停时必须告诉系统速率为零。
        let playbackRate: Double
        if case .playing = player.state, player.control == .playing {
            playbackRate = player.rate
        } else {
            playbackRate = 0
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = player.rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.current
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastReportedTime = player.current
        lastReportedRate = player.rate
    }
    
    public func cleanPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    deinit {
        cleanCommand()
    }
    
    /// 设置播放信息
    ///
    /// - Parameters:
    ///   - title: 标题
    ///   - artist: 作者
    ///   - cover: 封面
    ///   - url: 链接
    open func set(title: String, artist: String, cover: UIImage? = nil, url: URL) {
        var info: [String : Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        
        if #available(iOS 10.3, *) {
            // 当前URL
            info[MPNowPlayingInfoPropertyAssetURL] = url
        }
        
        if let cover = cover {
            // 封面图
            let artwork = MPMediaItemArtwork(
                boundsSize: cover.size,
                requestHandler: { (size) -> UIImage in
                    return cover
                }
            )
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        // 媒体类型
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updatePlayingInfo()
    }

    @objc
    private func playCommandAction(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch player.state {
        case .playing where player.control == .pausing:
            player.play()
            return .success
            
        case .finished where player.control == .pausing:
            player.play()
            return .success
            
        default:
            return .noSuchContent
        }
    }
    
    @objc
    private func pauseCommandAction(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard case .playing = player.state else { return .noSuchContent }
        guard player.control == .playing else { return .noSuchContent }
        
        player.pause()
        return .success
    }
}

extension AudioPlayerRemoteControl: AudioPlayerDelegate {
    
    public func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        updatePlayingInfo()
    }
    
    public func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        updatePlayingInfo()
    }
    
    public func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .prepare:
            cleanPlayingInfo()
            
        case .playing:
            setupCommand()
            
        case .stopped:
            cleanCommand()
            cleanPlayingInfo()
            
        case .finished:
            updatePlayingInfo()
            
        case .failed:
            cleanCommand()
            cleanPlayingInfo()
        }
    }
    
    public func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        // 播放时钟由系统推算，媒体时间累计偏移超过五秒或倍速改变时校准，避免每秒十次重写锁屏信息。
        if abs(time - lastReportedTime) > 5 || player.rate != lastReportedRate {
            updatePlayingInfo()
        }
    }
    
    public func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        updatePlayingInfo()
    }
    
    public func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek) {
        updatePlayingInfo()
    }
}
