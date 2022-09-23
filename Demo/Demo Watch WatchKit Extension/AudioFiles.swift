//
//  AudioFiles.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import Foundation

enum AudioFiles {
    
    struct File {
        let id: String
        let url: URL
    }
    
    static let directory: URL = {
        return FileManager.default.temporaryDirectory.appendingPathComponent("audios", isDirectory: true)
    } ()
    
    static var files: [File] {
        get { UserDefaults.standard.value(forKey: "com.watch.audio.files") as? [File] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "com.watch.audio.files") }
    }
    
    static func file(for id: String) -> File? {
        return files.first(where: { $0.id == id })
    }
}
