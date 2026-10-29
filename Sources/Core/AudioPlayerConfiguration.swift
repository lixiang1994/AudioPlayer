//
//  AudioPlayerConfiguration.swift
//  AudioPlayer
//
//  Created by 李响 on 2022/7/14.
//

import Foundation

public struct AudioPlayerConfiguration {

    /// 是否处理 interruption、route change 和 media services reset 通知，默认 true。
    /// 宿主统一管理 AVAudioSession 时设为 false，并由宿主负责中断、路由及重置恢复策略。
    /// 创建实例后固定；不影响应用前后台通知，也不配置或激活音频会话。
    public var handlesAudioSessionNotifications: Bool = true
    
    /// 是否自动播放 默认: true
    public var isAutoplay: Bool = true
    
    /// 预缓冲时长 默认 0 自动选择
    public var preferredBufferDuration: TimeInterval = 0
    
    /// 当前时间回调周期间隔 每秒次数 默认: 每秒10次
    public var currentTimeCallbackPeriodicInterval: UInt = 10
    
    public init() {
        
    }
}
