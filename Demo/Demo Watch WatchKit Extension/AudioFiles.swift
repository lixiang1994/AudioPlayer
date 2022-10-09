//
//  AudioFiles.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import Foundation

enum AudioFiles {
    
    static let didChanged = Notification.Name("com.audio.files.changed")
    
    struct File: Equatable, Codable {
        let id: String 
        let pathExtension: String /// 文件扩展名
    }
    
    static let directory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let url = urls.first!.appendingPathComponent(
            "audios",
            isDirectory: true
        )
        // 判断是否已经存在 不存在则创建目录
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                atPath: url.path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return url
    } ()
    
    private(set) static var files: [File] {
        get { UserDefaults.standard.model(forKey: "com.watch.audio.files") ?? [] }
        set {
            UserDefaults.standard.set(model: newValue, forKey: "com.watch.audio.files")
            NotificationCenter.default.post(name: AudioFiles.didChanged, object: nil)
        }
    }
    
    static var ids: [String] {
        return files.map({ $0.id })
    }
    
    static func file(for id: String) -> File? {
        return files.first(where: { $0.id == id })
    }
    
    static func url(for id: String) -> URL? {
        guard let file = file(for: id) else {
            return nil
        }
        return directory.appendingPathComponent(
            "\(file.id).\(file.pathExtension)"
        )
    }
    
    static func contains(_ id: String) -> Bool {
        return files.contains(where: { $0.id == id })
    }
    
    static func append(_ file: File) {
        files.removeAll(where: { $0.id == file.id })
        files.append(file)
    }
    
    @discardableResult
    static func remove(at id: String) -> File? {
        guard let index = files.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return files.remove(at: index)
    }
}
