//
//  AudioPlayerQueue.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import Foundation

class AudioPlayerQueue {
    
    typealias Item = AudioPlayerItem
    
    private(set) var items: [Item] = []
    
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
    
    /// 随机
    /// - Parameter item: 项目
    /// - Returns: 如果队列内项目个数仅为1个 则直接返回传入的Item, 大于1个时 随机返回一个不等于传入Item的Item
    func random(of item: Item) -> Item? {
        guard items.count > 1 else {
            return item
        }
        return items.filter({ $0 != item }).randomElement()
    }
}
