//
//  WatchSession.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/5.
//

import Foundation
import WatchConnectivity

class WatchSession: NSObject {
    
    private struct Wrapper<T: Codable>: Codable {
        let value: T
    }
    
    static let shared = WatchSession()
    
    private var handlers: [String: ([String: Any])->Void] = [:]
    
    override init() {
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension WatchSession: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("\(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let id = file.metadata?["id"] else { return }
        
        let target = AudioFiles.directory.appendingPathComponent(
            "\(id).\(file.fileURL.pathExtension)",
            isDirectory: true
        )
        
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: target)
            
        } catch {
            print(error)
        }
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
    
    func send<T: Codable>(message model: T, for identifier: String) {
        do {
            let data = try JSONEncoder().encode(Wrapper(value: model))
            let json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            WCSession.default.sendMessage(
                ["identifier": identifier, "data": json],
                replyHandler: nil
            )
            
        } catch {
            print(error)
        }
    }
}
