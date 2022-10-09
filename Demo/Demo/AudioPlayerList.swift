//
//  AudioPlayerList.swift
//  Demo
//
//  Created by 李响 on 2022/9/29.
//

import Foundation

class AudioPlayerList {
    
    /// 模拟数据源 可能是来自网络 也可能是来自其他
    static let items: [AudioPlayerItem] = {
        guard
            let url = Bundle.main.url(forResource: "audios", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([AudioPlayerItem].self, from: data)
            
        } catch {
            return []
        }
    } ()
    
    static func item(for id: String) -> AudioPlayerItem? {
        return items.first(where: { $0.id == id })
    }
}
