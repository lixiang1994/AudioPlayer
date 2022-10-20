//
//  WatchSessionState.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/10/20.
//

import Foundation

class WatchSessionState: ObservableObject {
    
    static let shared = WatchSessionState()
    
    /// 是否已激活
    @Published
    var isActivated: Bool = false
    
    /// 是否可访问
    @Published
    var isReachable: Bool = false
    
    /// 是否已安装关联应用
    @Published
    var isCompanionAppInstalled: Bool = false
}
