//
//  AudioPlayerRemote.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import MediaPlayer.MPNowPlayingInfoCenter
import MediaPlayer.MPRemoteCommandCenter

open class AudioPlayerRemote: NSObject {
    
    public let player: AudioPlayerable
    
    public init(_ player: AudioPlayerable) {
        self.player = player
        super.init()
        setup()
    }
    
    /// 设置远程控制
    open func setup() {
        clean()
        
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.addTarget(self, action: #selector(playCommandAction))
        remote.pauseCommand.addTarget(self, action: #selector(pauseCommandAction))
        
        updatePlayingInfo()
    }
    
    /// 清理远程控制
    open func clean() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.removeTarget(self)
        remote.pauseCommand.removeTarget(self)
    }
    
    /// 更新播放信息
    public func updatePlayingInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyPlaybackDuration] = player.duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.current
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    deinit {
        clean()
    }
    
    /// 设置播放信息
    ///
    /// - Parameters:
    ///   - title: 标题
    ///   - artist: 作者
    ///   - thumb: 封面
    ///   - url: 链接
    open func set(title: String, artist: String, thumb: UIImage, url: URL) {
        var info: [String : Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        
        if #available(iOS 10.3, *) {
            // 当前URL
            info[MPNowPlayingInfoPropertyAssetURL] = url
        }
        
        if #available(iOS 10.0, *) {
            // 封面图
            let artwork = MPMediaItemArtwork(
                boundsSize: thumb.size,
                requestHandler: { (size) -> UIImage in
                    return thumb
            })
            info[MPMediaItemPropertyArtwork] = artwork
            // 媒体类型
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            
        } else {
            // 封面图
            let artwork = MPMediaItemArtwork(image: thumb)
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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

extension AudioPlayerRemote: AudioPlayerDelegate {
    
    public func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        updatePlayingInfo()
    }
    
    public func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        updatePlayingInfo()
    }
    
    public func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .prepare:
            clean()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            
        case .playing:
            setup()
            
        case .stopped:
            clean()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            
        case .finished:
            updatePlayingInfo()
            
        case .failure:
            clean()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    public func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        updatePlayingInfo()
    }
    
    public func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek) {
        updatePlayingInfo()
    }
}
