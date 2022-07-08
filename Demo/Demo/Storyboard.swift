//
//  StoryBoard.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit

public struct Storyboard {
    
    private let name: String
    private let bundle: Bundle?
    
    public init(_ name: String, in bundle: Bundle? = nil) {
        self.name = name
        self.bundle = bundle
    }
    
    private var storyboard: UIStoryboard {
        return UIStoryboard(name: name, bundle: bundle)
    }
    
    public func instance<T>() -> T {
        return storyboard.instantiateViewController(withIdentifier: String(describing: T.self)) as! T
    }
}

extension Storyboard {
    
    static let main = Storyboard("Main")
}
