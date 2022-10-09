//
//  DemoApp.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/1.
//

import SwiftUI

@main
struct DemoApp: App {
    
    @State private var selection = 0
    
    @SceneBuilder var body: some Scene {
        WindowGroup {
            TabView(selection: $selection) {
                NavigationView {
                    AudioPlayerView()
                }.tag(0)
                
                NavigationView {
                    AudioPlayerQueueView()
                }.tag(1)
            }
        }


        WKNotificationScene(controller: NotificationController.self, category: "myCategory")
    }
}
