//
//  AudioPlayerPhoneList.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/26.
//

import Foundation

class AudioPlayerPhoneList: ObservableObject {
    
    static let shared = AudioPlayerPhoneList()
    
    @Published
    private(set) var items: [AudioPlayerItem] = []

    init() {
        // 接收队列信息
        WatchSession.shared.receive(handle: { [weak self] (model: [Watch.Data.Item]) in
            guard let self = self else { return }
            self.items = model.map({ item in
                AudioPlayerItem(item)
            })
            
        }, for: Watch.Identifier.Player.Queue)
        
        // 主动发起同步
        sync()
    }
    
    func sync() {
        WatchSession.shared.request(for: Watch.Identifier.Player.Sync)
    }
}
