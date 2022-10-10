//
//  WatchSession.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import WatchConnectivity

class WatchSession: NSObject {
    
    static let CompanionAppInstalledDidChange = Notification.Name(rawValue: "CompanionAppInstalledDidChange")
    static let ReachabilityDidChange = Notification.Name(rawValue: "ReachabilityDidChange")
    
    /// 是否安装了配套应用
    static var isCompanionAppInstalled: Bool {
        return WCSession.default.isCompanionAppInstalled
    }
    
    /// 是否可访问
    static var isReachable: Bool {
        return WCSession.default.isReachable
    }
    
    private struct Wrapper<T: Codable>: Codable {
        let value: T
    }
    
    typealias Response<T> = Swift.Result<T, Swift.Error>
    
    static let shared = WatchSession()
    
    private var handlers: [String: ([String: Any], ([String: Any])->Void) -> Void] = [:]
    
    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension WatchSession: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("\(activationState.rawValue)")
    }
    
    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        NotificationCenter.default.post(
            name: WatchSession.CompanionAppInstalledDidChange,
            object: nil,
            userInfo: [:]
        )
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        NotificationCenter.default.post(
            name: WatchSession.ReachabilityDidChange,
            object: nil,
            userInfo: [:]
        )
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("didReceiveApplicationContext: \(applicationContext)")
    }
    
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        print("didFinish: \(userInfoTransfer.userInfo)")
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        print("didFinish: \(fileTransfer)")
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        guard
            let identifier = userInfo["identifier"] as? String,
            let data = userInfo["data"] as? [String: Any] else {
            return
        }
        switch identifier {
        case Watch.Identifier.Sync.List:    // 同步音频列表
            guard let list = data["list"] as? [[String: Any]] else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: list)
                let model = try JSONDecoder().decode([Watch.Data.Item].self, from: data)
                let items = model.map({ AudioPlayerItem($0) })
                // 设置本地列表
                AudioPlayerWatchList.shared.set(items)
                // 对比音频文件 删除不包含在新列表中的文件
                let new = Set(items.map({ $0.id }))
                let old = Set(AudioFiles.ids)
                old.subtracting(new).forEach({
                    guard let file = AudioFiles.remove(at: $0) else { return }
                    let target = AudioFiles.directory.appendingPathComponent(
                        "\(file.id).\(file.pathExtension)"
                    )
                    try? FileManager.default.removeItem(at: target)
                })
                
            } catch {
                print(error)
            }
            
        default:
            break
        }
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard
            let identifier = file.metadata?["identifier"] as? String,
            let data = file.metadata?["data"] as? [String: Any] else {
            return
        }
        
        switch identifier {
        case Watch.Identifier.Sync.File:    // 同步音频文件
            guard let id = data["id"] as? String else { return }
            
            let target = AudioFiles.directory.appendingPathComponent(
                "\(id).\(file.fileURL.pathExtension)"
            )
            
            do {
                // 将文件从临时存储目录移动到指定目录
                if FileManager.default.fileExists(atPath: target.path) {
                    // 如果目标路径存在 则先清理
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: file.fileURL, to: target)
                // 添加音频文件记录
                AudioFiles.append(.init(id: id, pathExtension: file.fileURL.pathExtension))
                
            } catch {
                print(error)
            }
        
        default:
            break
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard
            let identifier = message["identifier"] as? String,
            let data = message["data"] as? [String: Any] else {
            return
        }
        DispatchQueue.main.async {
            self.handlers[identifier]?(data, replyHandler)
        }
    }
    
    func receive(handle: @escaping () -> Void, for identifier: String) {
        receive(handle: { (void: Watch.Data.Void) in
            handle()
        }, for: identifier)
    }
    
    func receive<T: Codable>(handle: @escaping (T) -> Void, for identifier: String) {
        receive(handle: { model in
            handle(model)
            return Watch.Data.Void()
        }, for: identifier)
    }
    
    func receive<R: Codable>(handle: @escaping () -> R, for identifier: String) {
        receive(handle: { (void: Watch.Data.Void) -> R in
            return handle()
        }, for: identifier)
    }
    
    func receive<T: Codable, R: Codable>(handle: @escaping (T) -> R, for identifier: String) {
        handlers[identifier] = { (data, reply) in
            do {
                let data = try JSONSerialization.data(withJSONObject: data)
                let model = try JSONDecoder().decode(Wrapper<T>.self, from: data)
                
                if
                    let data = try? JSONEncoder().encode(Wrapper(value: handle(model.value))),
                    let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
                    reply(json as! [String: Any])
                    
                } else {
                    reply([:])
                }
                
            } catch {
                print(error)
            }
        }
    }
    
    func request(for identifier: String) {
        request(message: Watch.Data.Void(), for: identifier)
    }
    
    func request<T: Codable>(message model: T?, for identifier: String) {
        request(message: model, for: identifier) { _ in }
    }
    
    func request<T: Codable>(message model: T?, for identifier: String, with completion: @escaping (Bool) -> Void) {
        request(message: model, for: identifier) { (result: Response<Watch.Data.Void>) in
            switch result {
            case .success:
                completion(true)
                
            case .failure:
                completion(false)
            }
        }
    }
    
    func request<R: Codable>(for identifier: String, with completion: @escaping (Response<R>) -> Void) {
        request(message: Watch.Data.Void(), for: identifier, with: completion)
    }
    
    func request<T: Codable, R: Codable>(message model: T?, for identifier: String, with completion: @escaping (Response<R>) -> Void) {
        
        var message: [String: Any] = ["identifier": identifier]
        if
            let model = model,
            let data = try? JSONEncoder().encode(Wrapper(value: model)),
            let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            message["data"] = json
            
        } else {
            message["data"] = ["value": [:]]
        }
        
        WCSession.default.sendMessage(
            message,
            replyHandler: { info in
                DispatchQueue.main.async {
                    do {
                        let data = try JSONSerialization.data(withJSONObject: info)
                        let model = try JSONDecoder().decode(Wrapper<R>.self, from: data)
                        completion(.success(model.value))
                        
                    } catch {
                        completion(.failure(error))
                    }
                }
            },
            errorHandler: { error in
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        )
    }
}
