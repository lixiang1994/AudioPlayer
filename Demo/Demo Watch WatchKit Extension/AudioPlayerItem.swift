//
//  AudioPlayerItem.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
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
