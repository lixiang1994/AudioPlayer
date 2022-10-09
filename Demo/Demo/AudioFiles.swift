//
//  AudioFiles.swift
//  Demo
//
//  Created by 李响 on 2022/9/29.
//

import Foundation

enum AudioFiles {
    
    static let didChanged = Notification.Name("com.audio.files.changed")
    
    struct File: Equatable, Codable {
        let id: String
        let pathExtension: String /// 文件扩展名
    }
    
    static let directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
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
        files.append(file)
    }
    
    static func remove(at id: String) {
        files.removeAll(where: { $0.id == id })
    }
}
