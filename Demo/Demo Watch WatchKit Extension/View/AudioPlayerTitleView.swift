//
//  AudioPlayerTitleView.swift
//  Demo Watch WatchKit Extension
//
//  Created by 李响 on 2022/10/24.
//

import SwiftUI
import Combine

struct AudioPlayerTitleView: View {
    
    /// 标题
    public let title: (String, UIFont)
    /// 子标题
    public let subtitle: (String, UIFont)
    
    @State
    private var titleOffset: CGFloat = 0
    @State
    private var subtitleOffset: CGFloat = 0
    @State
    private var isAnimation: Bool = true
    @Environment(\.isLuminanceReduced)
    private var isLuminanceReduced
    
    /// 计时器 每16毫秒一次
    private let timer = Timer.publish(every: 0.016, on: .main, in: .default).autoconnect()
    
    /// 延迟3秒
    private let delay = 3.0
    /// 速度每秒
    private let speed = 30.0
    
    var body: some View {
        
        let titleSize = title.0.sizeOfString(usingFont: title.1)
        let subtitleSize = subtitle.0.sizeOfString(usingFont: subtitle.1)
        let initialOffset = delay * speed
        let padding = 16.0
        
        GeometryReader { geo in
            VStack {
                ZStack {
                    let offset = (titleOffset > 0 ? titleOffset : 0)
                    
                    Text(title.0)
                        .lineLimit(1)
                        .font(.init(title.1))
                        .offset(x: 0 - offset)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
                    
                    Text(title.0)
                        .lineLimit(1)
                        .font(.init(title.1))
                        .offset(x: titleSize.width + titleSize.height * 2 - offset)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
                        .opacity(titleSize.width > geo.size.width ? 1 : 0)
                }
                .offset(x: padding)
                .mask(
                    HStack(spacing:0) {
                        Rectangle()
                            .frame(width:2)
                            .opacity(0)
                        LinearGradient(
                            gradient: Gradient(colors: [.black.opacity(0), .black]),
                            startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/
                        ).frame(width:padding)
                        LinearGradient(
                            gradient: Gradient(colors: [.black, .black]),
                            startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/
                        )
                        LinearGradient(
                            gradient: Gradient(colors: [.black, .black.opacity(0)]),
                            startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/
                        ).frame(width:padding)
                        Rectangle()
                            .frame(width:2)
                            .opacity(0)
                    }
                )
                .frame(width: geo.size.width + padding, height: titleSize.height)
                .offset(x: -padding)
                
                ZStack {
                    let offset = (subtitleOffset > 0 ? subtitleOffset : 0)
                    
                    Text(subtitle.0)
                        .lineLimit(1)
                        .font(.init(subtitle.1))
                        .offset(x: 0 - offset)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
                    
                    Text(subtitle.0)
                        .lineLimit(1)
                        .font(.init(subtitle.1))
                        .offset(x: subtitleSize.width + subtitleSize.height * 2 - offset)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
                        .opacity(subtitleSize.width > geo.size.width ? 1 : 0)
                }
                .offset(x: padding)
                .mask(
                    HStack(spacing:0) {
                        Rectangle()
                            .frame(width:2)
                            .opacity(0)
                        LinearGradient(
                            gradient: Gradient(colors: [.black.opacity(0), .black]),
                            startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/
                        ).frame(width:padding)
                        LinearGradient(
                            gradient: Gradient(colors: [.black, .black]),
                            startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/
                        )
                        LinearGradient(
                            gradient: Gradient(colors: [.black, .black.opacity(0)]),
                            startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/
                        ).frame(width:padding)
                        Rectangle()
                            .frame(width:2)
                            .opacity(0)
                    }
                )
                .frame(width: geo.size.width + padding, height: subtitleSize.height)
                .offset(x: -padding)
            }
            .onReceive(timer, perform: { time in
                guard isAnimation else { return }
                
                if titleSize.width > geo.size.width {
                    // 判断偏移结束
                    if titleOffset > titleSize.width + titleSize.height * 2 {
                        // 确认子标题比主标题长
                        if subtitleSize.width > titleSize.width {
                            let diff = subtitleSize.width + subtitleSize.height * 2 - subtitleOffset
                            // 重置初始偏移量 - 子标题剩余偏移
                            titleOffset = -initialOffset - diff
                            
                        } else {
                            // 重置初始偏移量
                            titleOffset = -initialOffset
                        }
                        
                    } else {
                        titleOffset += speed / 60.0
                    }
                }
                
                if subtitleSize.width > geo.size.width {
                    // 判断偏移结束
                    if subtitleOffset > subtitleSize.width + subtitleSize.height * 2 {
                        // 确认主标题比子标题长
                        if titleSize.width > subtitleSize.width {
                            let diff = titleSize.width + titleSize.height * 2 - titleOffset
                            // 重置初始偏移量 - 主标题剩余偏移
                            subtitleOffset = -initialOffset - diff
                            
                        } else {
                            // 重置初始偏移量
                            subtitleOffset = -initialOffset
                        }
                        
                    } else {
                        subtitleOffset += speed / 60.0
                    }
                }
            })
            .onChange(of: title.0) { text in
                // 重置初始偏移量
                titleOffset = -initialOffset
                subtitleOffset = -initialOffset
            }
            .onChange(of: subtitle.1) { text in
                // 重置初始偏移量
                titleOffset = -initialOffset
                subtitleOffset = -initialOffset
            }
            .onChange(of: isLuminanceReduced, perform: { isLuminanceReduced in
                isAnimation = !isLuminanceReduced
                // 重置初始偏移量
                titleOffset = -initialOffset
                subtitleOffset = -initialOffset
            })
            .onAppear {
                isAnimation = true
            }
            .onDisappear {
                isAnimation = false
            }
        }
    }
}

struct AudioPlayerTitleView_Previews: PreviewProvider {
    static var previews: some View {
        AudioPlayerTitleView(
            title: ("Guru为北京/成都的各位程序员们准备了“1024专属下午茶”", .systemFont(ofSize: 16)),
            subtitle: ("LEE", .systemFont(ofSize: 12))
        )
    }
}

fileprivate extension String {
    
    func sizeOfString(usingFont font: UIFont) -> CGSize {
        return self.size(withAttributes: [.font: font])
    }
}
