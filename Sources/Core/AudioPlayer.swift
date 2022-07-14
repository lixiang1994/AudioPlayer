//
//  AudioPlayer.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import Foundation

public enum AudioPlayer {
    /// 播放状态
    /// stopped -> prepare -> playing -> finished
    public enum State {
        /// 准备播放: 调用`prepare(resource:)`后的状态.
        case prepare
        /// 正在播放: `prepare`处理完成后的状态,  当`finished`状态时再次调用`play()`也会回到该状态.
        case playing
        /// 播放停止: 默认的初始状态, 调用`stop()`后的状态.
        case stopped
        /// 播放完成: 在`isLoop = false`时会触发.
        case finished
        /// 播放失败: 调用`prepare(resource:)`后的任何时候 只要发生了异常便会触发该状态.
        case failed(Swift.Error?)
    }
    
    /// 控制状态: 仅在 state 为 .playing 状态时可用
    public enum ControlState {
        /// 播放中
        case playing
        /// 暂停中
        case pausing
    }
    
    /// 加载状态
    public enum LoadingState {
        /// 已开始
        case began
        /// 已结束
        case ended
    }
    
    public struct Seek {
        /// 目标时间 (秒)
        public let time: TimeInterval
        /// 完成回调 (成功为true, 失败为false, 失败可能是由于网络问题或被其他Seek抢占导致的)
        let completion: ((Bool) -> Void)?
        
        public init(time: TimeInterval, completion: ((Bool) -> Void)? = .none) {
            self.time = time
            self.completion = completion
        }
    }
}

extension AudioPlayer {
    
    public class Builder {
        
        public typealias Generator = (AudioPlayerConfiguration) -> AudioPlayerable
        
        private var generator: Generator
        
        public private(set) lazy var shared = generator(.init())
        
        public init(_ generator: @escaping Generator) {
            self.generator = generator
        }
        
        public func instance(_ configuration: AudioPlayerConfiguration = .init()) -> AudioPlayerable {
            return generator(configuration)
        }
    }
}
