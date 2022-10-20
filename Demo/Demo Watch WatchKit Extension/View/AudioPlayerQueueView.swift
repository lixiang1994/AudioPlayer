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
    
    @ObservedObject
    private var phone = AudioPlayerPhoneList.shared
    
    @ObservedObject
    private var watch = AudioPlayerWatchList.shared
    
    @State
    private var selected: Int = 0
    
    private var color = Color(red: 0.95, green: 0.96, blue: 0.99, opacity: 0.14)
    
    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Button {
                    selected = 0
                    
                } label: {
                    Image("source_phone")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected == 0 ? Color.red : color)
                .cornerRadius(10)
                
                Button {
                    selected = 1
                    
                } label: {
                    Image("source_watch")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected == 1 ? Color.red : color)
                .cornerRadius(10)
            }
            
            switch selected {
            case 0:
                List(phone.items, id: \.id) { item in
                    let isCurrent = item.id == manager.item?.id && manager.source == .phone
                    
                    Button {
                        guard !isCurrent else { return }
                        
                        AudioPlayerManager.shared.play(item, for: .init(phone.items), in: .phone)
                        
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isCurrent ? .red : .white)
                            
                            HStack {
                                Text(item.author)
                                    .lineLimit(1)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.64))
                                
                                Spacer()
                                
                                Image("list_cloud")
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .opacity(0.0)
                            }
                        }
                        
                    }.frame(height: 61)
                    
                }.onAppear {
                    phone.sync()
                }
                
            case 1:
                List(watch.items, id: \.id) { item in
                    let isCurrent = item.id == manager.item?.id && manager.source == .watch
                    
                    Button {
                        guard !isCurrent else { return }
                        
                        AudioPlayerManager.shared.play(item, for: manager.queue, in: .watch)
                        
                    } label: {
                        VStack(alignment: .leading) {
                            
                            Text(item.title)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isCurrent ? .red : .white)
                            
                            HStack {
                                Text(item.author)
                                    .lineLimit(1)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.64))
                                
                                Spacer()
                                
                                Image("list_cloud")
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .opacity(AudioFiles.contains(item.id) ? 0.0 : 1.0)
                            }
                            
                        }.frame(height: 61)
                    }
                }
                
            default:
                Text("空")
            }
        }
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selected = manager.source.rawValue
        }
    }
}

struct AudioPlayerQueueView_Previews: PreviewProvider {
    static var previews: some View {
        AudioPlayerQueueView()
    }
}
