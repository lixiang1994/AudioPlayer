//
//  AudioPlayerQueueView.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/21.
//

import SwiftUI

struct AudioPlayerQueueView: View {
    
    @ObservedObject
    private var manager = AudioPlayerManager.shared
    
    var body: some View {
        List(manager.queue.items, id: \.id) { item in
            Button {
                guard item.id != manager.item?.id else { return }
                
                manager.play(item, for: manager.queue)
                
            } label: {
                Text(item.title)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(item.id == manager.item?.id ? .red : .white)
            }
        }
        .navigationTitle("Next Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AudioPlayerQueueView_Previews: PreviewProvider {
    static var previews: some View {
        AudioPlayerQueueView()
    }
}
