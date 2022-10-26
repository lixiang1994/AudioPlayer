//
//  AudioPlayerView.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/9/1.
//

import SwiftUI
import AVFoundation
import MediaPlayer

struct AudioPlayerView: View {
    
    @ObservedObject
    private var manager = AudioPlayerManager.shared
    
    @Environment(\.scenePhase)
    private var scenePhase
    
    @State
    private var isShowAlert = false
    
    var body: some View {
        ZStack {
            
            switch manager.source {
            case .phone:
                VolumeView(origin: .companion).opacity(0)
                
            case .watch:
                VolumeView(origin: .local).opacity(0)
            }
            
            VStack {
                
                Spacer(minLength: 8)
                
                AudioPlayerTitleView(
                    title: (manager.item?.title ?? "没有正在播放的内容", .systemFont(ofSize: 15, weight: .semibold)),
                    subtitle: (manager.item?.author ?? " ", .systemFont(ofSize: 13))
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                
                Spacer()
                
                HStack {
                    Button {
                        AudioPlayerManager.shared.prev()

                    } label: {
                        Image("prev")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    .frame(width: 40, height: 40)
                    .buttonStyle(.plain)
                    .disabled(!manager.switchable.prev)
                    
                    Spacer()
                    
                    Button {
                        if manager.controlState == .playing {
                            AudioPlayerManager.shared.pause()
                            
                        } else {
                            AudioPlayerManager.shared.play()
                        }
                        
                    } label: {
                        CircleProgressView(value: $manager.progress) {
                            if manager.controlState == .playing {
                                Image("pause")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)

                            } else {
                                Image("play")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .buttonStyle(.plain)
                    .disabled(playButtonDisabled())

                    Spacer()
                    
                    Button {
                        AudioPlayerManager.shared.next()
                        
                    } label: {
                        Image("next")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    .frame(width: 40, height: 40)
                    .buttonStyle(.plain)
                    .disabled(!manager.switchable.next)
                }
                .padding(.horizontal)
                .offset(y: 10)
                
                Spacer()
                
                HStack {
                    Button {
                        
                    } label: {
                        manager.source.icon
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .frame(width: 40, height: 40)
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        var temp = manager.rate + 0.1
                        if temp > 3.0 {
                            temp = 0.5
                        }
                        if temp == 0.6 {
                            temp = 0.8
                        }
                        AudioPlayerManager.shared.set(rate: temp)
                        
                    } label: {
                        Text("\(manager.rate, specifier: "%.1f")x")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .frame(width: 40, height: 40)
                    .buttonStyle(.plain)

                    Spacer()
                    
                    NavigationLink(destination: AudioPlayerSettingView()) {
                        Image("setting")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                    }
                    .frame(width: 40, height: 40)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .offset(y: 20)
                
            }.onAppear {
                AudioPlayerManager.shared.sync()
            }
            
            VStack(alignment: .trailing) {
                HStack {
                    Spacer()
                    
                    BarView(progress: $manager.volume)
                        .frame(width: 4, height: 36)
                        .padding(.top, 10)
                        .ignoresSafeArea(.container, edges: .trailing)
                }
                
                Spacer()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                AudioPlayerManager.shared.sync()
            }
        }
        .onChange(of: manager.state, perform: { state in
            isShowAlert = state == .failed(.none)
        })
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $isShowAlert) {
            Button("Retry") {
                manager.replay()
            }
            Button("Cancel") {

            }

        } message: {
            Text("Playback failed")
        }
    }
    
    
    private func playButtonDisabled() -> Bool {
        manager.item == nil || (manager.state == .prepare || manager.state == .stopped)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AudioPlayerView()
                .previewDevice("Apple Watch Series 5 - 40mm")
            AudioPlayerView()
                .previewDevice("Apple Watch Series 7 - 41mm")
            AudioPlayerView()
                .previewDevice("Apple Watch Series 7 - 45mm")
        }
    }
}

struct CircleProgressView<Label>: View where Label: View {
    
    var colors: [Color] = [Color(#colorLiteral(red: 0.5764705882, green: 0.9607843137, blue: 0.9333333333, alpha: 1)), Color(#colorLiteral(red: 0.6549019608, green: 0.4823529412, blue: 0.9568627451, alpha: 1))]
    var lineWidth: CGFloat = 3
    
    @Binding var value: Double
    
    @ViewBuilder let label: Label
    
    var body: some View {
        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(lineWidth / 2)
            
            Circle()
                .stroke(
                    Color.white.opacity(0.42),
                    style: StrokeStyle(lineWidth: lineWidth)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            
            Circle()
                .trim(from: 1.0 - value, to: 1)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(
                            colors: colors
                        ),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .rotationEffect(Angle(degrees: 90))
                .rotation3DEffect(
                    Angle(degrees: 180),
                    axis: (x: 1, y: 0, z: 0)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            
            label
        }
    }
}

struct VolumeView: WKInterfaceObjectRepresentable {
    
    typealias WKInterfaceObjectType = WKInterfaceVolumeControl
    
    let origin: WKInterfaceVolumeControl.Origin
    
    func makeWKInterfaceObject(context: Self.Context) -> WKInterfaceVolumeControl {
        return WKInterfaceVolumeControl(origin: origin)
    }
    
    func updateWKInterfaceObject(_ wkInterfaceObject: WKInterfaceVolumeControl, context: WKInterfaceObjectRepresentableContext<VolumeView>) {
        wkInterfaceObject.focus()
    }
    
    static func dismantleWKInterfaceObject(_ wkInterfaceObject: WKInterfaceVolumeControl, coordinator: ()) {
        wkInterfaceObject.resignFocus()
    }
}

struct BarView: View {
    
    @Binding
    var progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule()
                    .foregroundColor(Color.white.opacity(0.3))
                Capsule()
                    .frame(height: min(max(geometry.size.height * progress, 0), geometry.size.height))
                    .animation(.linear, value: progress)
            }
        }
    }
}

fileprivate extension AudioPlayerManager.Source {
    
    var icon: Image {
        switch self {
        case .phone:
            return Image("source_phone")
        case .watch:
            return Image("source_watch")
        }
    }
}
