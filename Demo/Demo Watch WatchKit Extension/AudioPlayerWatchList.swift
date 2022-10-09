//
//  AudioPlayerWatchList.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/26.
//

import Foundation

class AudioPlayerWatchList: ObservableObject {
    
    static let shared = AudioPlayerWatchList()
    
    @Published
    var items: [AudioPlayerItem] = []
    
    private var cache: [AudioPlayerItem] {
        get { UserDefaults.standard.model(forKey: "com.watch.list.items") ?? [] }
        set { UserDefaults.standard.set(model: newValue, forKey: "com.watch.list.items") }
    }
    
    init() {
        items = cache
        
        // 监听音频文件变动
        NotificationCenter.default.addObserver(forName: AudioFiles.didChanged, object: nil, queue: .main) { [weak self] sender in
            guard let self = self else { return }
            // 主动触发更新
            self.objectWillChange.send()
        }
        
        // 接收同步列表
        WatchSession.shared.receive(handle: { () -> [String] in
            return AudioFiles.ids
            
        }, for: Watch.Identifier.Sync.List)
    }
    
    func set(_ items: [AudioPlayerItem]) {
        self.items = items
        self.cache = items
    }
}
