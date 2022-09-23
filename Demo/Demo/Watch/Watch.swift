//
//  Watch.swift
//  Demo
//
//  Created by 李响 on 2022/9/5.
//

import Foundation

enum Watch {
    
    enum Identifier {
        
        enum Player {
            static let Play = "com.audio.player.play"
            
            static let Queue = "com.audio.player.queue"
            static let Item = "com.audio.player.item"
            
            static let State = "com.audio.player.state"
            static let ControlState = "com.audio.player.control.state"
            static let LoadingState = "com.audio.player.loading.state"
            static let Prev = "com.audio.player.prev"
            static let Next = "com.audio.player.next"
            static let Rate = "com.audio.player.rate"
            static let Volume = "com.audio.player.volume"
            
            static let Buffer = "com.audio.player.buffer"
            static let Current = "com.audio.player.current"
            static let Duration = "com.audio.player.duration"
            
            static let Sync = "com.audio.player.sync"
        }
    }
    
    enum Data {
        
        struct Void: Codable {
            
        }
        
        struct Play: Codable {
            let item: Item
            let queue: [Item]
        }
        
        struct Item: Equatable, Codable {
            let id: String
            let title: String
            let cover: String
            let author: String
            let duration: TimeInterval
            let resource: URL
        }
    }
}
