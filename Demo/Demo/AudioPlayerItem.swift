//
//  AudioPlayerItem.swift
//  Demo
//
//  Created by 李响 on 2022/7/9.
//

import Foundation

struct AudioPlayerItem: Equatable {
    let id: String
    let title: String
    let cover: String
    let author: String
    let resource: URL
}

// 扩展Item 增加状态模拟
extension AudioPlayerItem {
    
    private var cache: [String: TimeInterval] {
        get {
            let key = "audio.player.records"
            return UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
        }
        set {
            let key = "audio.player.records"
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
    
    enum State {
        case record(Double)
        case played
    }
    
    /// 状态 (未播放, 播放进度, 已播放)
    var state: State? {
        get {
            guard let value = cache[id] else { return nil }
            return value < 0 ? .played : .record(value) 
        }
        set {
            switch newValue {
            case .record(let time):
                cache[id] = time
                
            case .played:
                cache[id] = -1
                
            default:
                cache[id] = nil
            }
        }
    }
}
