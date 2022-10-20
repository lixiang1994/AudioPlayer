//
//  DemoApp.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/1.
//

import SwiftUI

@main
struct DemoApp: App {
    
    @State
    private var selection = 0
    
    @ObservedObject
    private var state = WatchSessionState.shared
    
    init() {
        // 激活会话
        WatchSession.shared.activate()
    }
    
    @SceneBuilder var body: some Scene {
        WindowGroup {
            if !state.isActivated {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

            } else if !state.isCompanionAppInstalled {
                Text("Companion App Uninstalled.")

            } else if !state.isReachable {
                if WatchSession.iOSDeviceNeedsUnlockAfterRebootForReachability {
                    Text("Please unlock your paired iOS device.")

                } else {
                    Text("Unable to reach the companion app.")
                }

            } else {
                TabView(selection: $selection) {
                    NavigationView {
                        AudioPlayerView()
                    }.tag(0)
                    
                    NavigationView {
                        AudioPlayerQueueView()
                    }.tag(1)
                }   
            }
        }


        WKNotificationScene(controller: NotificationController.self, category: "myCategory")
    }
}
