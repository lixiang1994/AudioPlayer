//
//  WatchSession.swift
//  Demo
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import WatchConnectivity

class WatchSession: NSObject {
    
    /// 未完成的文件传输
    static var outstandingFileTransfers: [WCSessionFileTransfer] {
        return WCSession.default.outstandingFileTransfers
    }
    
    /// 是否安装了手表应用
    static var isWatchAppInstalled: Bool {
        return WCSession.default.isWatchAppInstalled
    }
    /// 是否已配对
    static var isPaired: Bool {
        return WCSession.default.isPaired
    }
    /// 是否可访问
    static var isReachable: Bool {
        return WCSession.default.isReachable
    }
    
    typealias Response<T> = Swift.Result<T, Swift.Error>
    
    private struct Wrapper<T: Codable>: Codable {
        let value: T
    }
    
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
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print(session.isReachable)
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        
    }
    
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        print("didFinish: \(userInfoTransfer.userInfo)")
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard
            let identifier = fileTransfer.file.metadata?["identifier"] as? String,
            let data = fileTransfer.file.metadata?["data"] as? [String: Any] else {
            return
        }
        
        switch identifier {
        case Watch.Identifier.Sync.File:    // 同步音频文件
            guard let id = data["id"] as? String else { return }
            
            NotificationCenter.default.post(
                name: .init("didFinishFileTransfer"),
                object: nil,
                userInfo: ["id": id]
            )
            
        default:
            break
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
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
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            return
        }
        
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
    
    
    /// 发送信息
    /// - Parameters:
    ///   - info: 信息
    ///   - identifier: 标识
    @discardableResult
    func send(info: [String: Any], for identifier: String) -> Bool {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            return false
        }
        WCSession.default.transferUserInfo(["identifier": identifier, "data": info])
        return true
    }
    
    /// 发送文件
    /// - Parameters:
    ///   - url: 文件URL
    ///   - info: 扩展信息
    ///   - identifier: 标识
    @discardableResult
    func send(file url: URL, info: [String: Any], for identifier: String) -> Bool {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            return false
        }
        WCSession.default.transferFile(url, metadata: ["identifier": identifier, "data": info])
        return true
    }
}
