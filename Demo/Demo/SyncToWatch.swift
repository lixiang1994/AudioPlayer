//
//  SyncToWatch.swift
//  Demo
//
//  Created by 李响 on 2022/9/29.
//

import Foundation
import WatchConnectivity

class SyncToWatch {
    
    enum State {
    case sending
    case finished
    case failed
    }
    
    static let stateChanged = Notification.Name("com.sync.to.watch.state.changed")
    
    static let shared = SyncToWatch()
    
    private(set) var ids: [String] {
        get { UserDefaults.standard.model(forKey: "com.sync.to.watch.all.ids") ?? [] }
        set { UserDefaults.standard.set(model: newValue, forKey: "com.sync.to.watch.all.ids") }
    }
    
    private var finished: [String] {
        get { UserDefaults.standard.model(forKey: "com.sync.to.watch.finish.ids") ?? [] }
        set {
            UserDefaults.standard.set(model: newValue, forKey: "com.sync.to.watch.finish.ids")
            NotificationCenter.default.post(name: SyncToWatch.stateChanged, object: nil)
        }
    }
    
    init() {
        // 监听文件传输完成
        NotificationCenter.default.addObserver(
            forName: .init("didFinishFileTransfer"),
            object: nil,
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            guard let id = sender.userInfo?["id"] as? String else { return }
            self.finished.append(id)
        }
    }
    
    /// 获取同步状态
    /// - Parameter id: id
    /// - Returns: 同步状态
    func state(for id: String) -> State? {
        guard ids.contains(id) else {
            return nil
        }
        
        let transfers = WatchSession.outstandingFileTransfers
        let current = transfers.first(where: { $0.file.id == id })
        if let current = current {
            return current.isTransferring ? .sending : .finished
            
        } else {
            return finished.contains(id) ? .finished : nil
        }
    }
    
    /// 取消同步
    /// - Parameter id: id
    func cancel(for id: String) {
        let transfers = WatchSession.outstandingFileTransfers
        let current = transfers.first(where: { $0.file.id == id })
        current?.cancel()
    }
    
    func sync(_ ids: [String], with completion: @escaping (Bool) -> Void) {
        // 获取手表ID列表
        AudioPlayerWatchSession.shared.request(for: Watch.Identifier.Sync.List)
        { (result: Swift.Result<[String], Swift.Error>) in
            switch result {
            case .success(let value):
                // 根据ids获取items
                let items = ids
                    .compactMap({ AudioPlayerList.item(for: $0) })
                    .map({ Watch.Data.Item($0) })
                
                if
                    let data = try? JSONEncoder().encode(items),
                    let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
                    
                    self.ids = ids
                    self.finished = value
                    
                    // 发送列表信息
                    AudioPlayerWatchSession.shared.send(
                        info: ["list": json],
                        for: Watch.Identifier.Sync.List
                    )
                    
                    // 取消正在传输中的文件 (不包含在列表中的)
                    WatchSession.outstandingFileTransfers
                        .filter({ !ids.contains($0.file.id ?? "") })
                        .forEach({ $0.cancel() })
                    
                    // 开始同步文件
                    for id in ids {
                        guard let url = AudioFiles.url(for: id) else {
                            continue
                        }
                        // 跳过正在传输中的
                        guard !WatchSession.outstandingFileTransfers.contains(where: { $0.file.id == id }) else {
                            continue
                        }
                        // 跳过手表中已存在的
                        guard !value.contains(id) else {
                            continue
                        }
                        
                        AudioPlayerWatchSession.shared.send(
                            file: url,
                            info: ["id": id],
                            for: Watch.Identifier.Sync.File
                        )
                    }
                    
                    completion(true)
                    
                } else {
                    completion(false)
                }
                
            case .failure:
                completion(false)
            }
        }
    }
}

fileprivate extension WCSessionFile {
    
    var id: String? {
        guard let metadata = metadata else { return nil }
        guard let identifier = metadata["identifier"] as? String else { return nil }
        guard let data = metadata["data"] as? [String: Any] else { return nil }
        guard identifier == Watch.Identifier.Sync.File else { return nil }
        return data["id"] as? String
    }
}
