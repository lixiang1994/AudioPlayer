//
//  AudioPlayerItem.swift
//  Demo
//
//  Created by 李响 on 2022/7/9.
//

import Foundation

struct AudioPlayerItem: Equatable, Codable {
    let id: String
    let title: String
    let cover: String
    let author: String
    let duration: TimeInterval
    let resource: URL
}

// 扩展Item 增加状态模拟
extension AudioPlayerItem {
    
    private var cache: [String: TimeInterval] {
        get {
            let key = "audio.player.records"
            return UserDefaults.standard.value(forKey: key) as? [String: TimeInterval] ?? [:]
        }
        set {
            let key = "audio.player.records"
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
    
    enum State {
        case record(Double)
        case played
        case failed
    }
    
    /// 状态 (未播放, 播放进度, 已播放, 播放失败)
    var state: State? {
        get {
            guard let value = cache[id] else { return nil }
            switch value {
            case -1:
                return .played
                
            case -2:
                return .failed
                
            default:
                return .record(value)
            }
        }
        set {
            switch newValue {
            case .record(let time):
                cache[id] = time
                
            case .played:
                cache[id] = -1.0
                
            case .failed:
                cache[id] = -2.0
                
            default:
                cache[id] = nil
            }
        }
    }
}
