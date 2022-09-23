//
//  WatchSession.swift
//  Demo
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import WatchConnectivity

class WatchSession: NSObject {
    
    private struct Wrapper<T: Codable>: Codable {
        let value: T
    }
    
    private var handlers: [String: ([String: Any])->Void] = [:]
    
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
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        print("File Transfer Finish")
        print(fileTransfer.file.metadata)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard
            let identifier = message["identifier"] as? String,
            let data = message["data"] as? [String: Any] else {
            return
        }
        handlers[identifier]?(data)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard
            let identifier = message["identifier"] as? String,
            let data = message["data"] as? [String: Any] else {
            return
        }
        handlers[identifier]?(data)
    }
    
    func receive(handle: @escaping () -> Void, for identifier: String) {
        receive(handle: { (void: Watch.Data.Void) in
            handle()
        }, for: identifier)
    }
    
    func receive<T: Codable>(handle: @escaping (T) -> Void, for identifier: String) {
        receive(handle: { (model: T?) in
            guard let model = model else { return }
            handle(model)
        }, for: identifier)
    }
    
    func receive<T: Codable>(handle: @escaping (T?) -> Void, for identifier: String) {
        handlers[identifier] = { (data) in
            do {
                let data = try JSONSerialization.data(withJSONObject: data)
                let model = try JSONDecoder().decode(Wrapper<T>.self, from: data)
                DispatchQueue.main.async {
                    handle(model.value)
                }
                
            } catch {
                DispatchQueue.main.async {
                    handle(.none)
                }
            }
        }
    }
    
    func send(for identifier: String) {
        send(message: Watch.Data.Void(), for: identifier)
    }
    
    func send<T: Codable>(message model: T?, for identifier: String) {
        guard WCSession.default.isReachable else {
            return
        }
        
        if
            let model = model,
            let data = try? JSONEncoder().encode(Wrapper(value: model)),
            let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            WCSession.default.sendMessage(
                ["identifier": identifier, "data": json],
                replyHandler: nil
            ) { error in
                print(error)
            }
            
        } else {
            WCSession.default.sendMessage(
                ["identifier": identifier, "data": [:]],
                replyHandler: nil
            ) { error in
                print(error)
            }
        }
    }
    
    func send(file url: URL, for id: String) {
        WCSession.default.outstandingFileTransfers
        WCSession.default.transferFile(url, metadata: ["id": id])
    }
}