//
//  AudioPlayerConfiguration.swift
//  AudioPlayer
//
//  Created by 李响 on 2022/7/14.
//

import Foundation

public struct AudioPlayerConfiguration {
    
    /// 是否自动播放 默认: true
    public var isAutoplay: Bool = true
    
    /// 预缓冲时长 默认 0 自动选择
    public var preferredBufferDuration: TimeInterval = 0
    
    /// 当前时间回调周期间隔 每秒次数 默认: 每秒10次
    public var currentTimeCallbackPeriodicInterval: UInt = 10
    
    public init() {
        
    }
}
