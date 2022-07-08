//
//  AudioPlayerRemoteControl.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import AudioPlayer
import MediaPlayer.MPNowPlayingInfoCenter
import MediaPlayer.MPRemoteCommandCenter

class AudioPlayerRemoteControl: AudioPlayerRemote {
    
    var playPrev: (()-> Void)?
    var playNext: (()-> Void)?
    
    override func setup() {
        super.setup()
        
        let remote = MPRemoteCommandCenter.shared()
        remote.previousTrackCommand.addTarget(self, action: #selector(prevCommandAction))
        remote.nextTrackCommand.addTarget(self, action: #selector(nextCommandAction))
        
    }
    
    override func clean() {
        super.clean()
        
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
    
    func set(switchable state: (Bool, Bool)) {
        let remote = MPRemoteCommandCenter.shared()
        remote.previousTrackCommand.isEnabled = state.0
        remote.nextTrackCommand.isEnabled = state.1
    }
}
