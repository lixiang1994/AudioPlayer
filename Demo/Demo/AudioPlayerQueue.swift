//
//  AudioPlayerQueue.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import Foundation

class AudioPlayerQueue {
    
    struct Item: Equatable {
        let id: String
        let title: String
        let cover: String
        let author: String
        let resource: URL
    }
    
    private var items: [Item] = []
    
    var count: Int {
        return items.count
    }
    
    init(_ items: [Item]) {
        self.items = items
    }
    
    /// 是否包含此项目
    /// - Parameter item: 项目
    func contains(_ item: Item) -> Bool {
        return items.contains(item)
    }
    
    func item(at index: Int) -> Item? {
        guard index >= 0, index < items.count else {
            return nil
        }
        return items[index]
    }
    
    /// 上一个
    func prev(of item: Item) -> Item? {
        guard let index = items.firstIndex(of: item) else {
            return nil
        }
        return items.prefix(index).last
    }
    func prev(of item: Item) -> Bool {
        return prev(of: item) != nil
    }
    
    /// 下一个
    func next(of item: Item) -> Item? {
        guard let index = items.firstIndex(of: item) else {
            return nil
        }
        return items.dropFirst(index + 1).first
    }
    func next(of item: Item) -> Bool {
        return next(of: item) != nil
    }
}
