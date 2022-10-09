//
//  AudioPlayerController.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit
import AudioPlayer

class AudioPlayerController: ViewController<AudioPlayerView> {
    
    private let manager = AudioPlayerManager.shared
    
    private var isDraging = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
        setupManager()
    }
    
    private func setup() {
        // 界面动画设置
        container.startAnmiation()
        container.pauseAnimation()
        
        // 为Slider添加事件
        container.slider.addTarget(self, action: #selector(sliderTouchBegin), for: .touchDown)
        container.slider.addTarget(self, action: #selector(sliderTouchEnd), for: [.touchUpInside, .touchUpOutside])
        container.slider.addTarget(self, action: #selector(sliderTouchCancel), for: .touchCancel)
        container.slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    }
    
    private func setupManager() {
        // 添加代理
        manager.add(delegate: self)
        manager.player.add(delegate: self)
        
        audioPlayerManager(manager, changed: manager.item)
        audioPlayerManager(manager, changed: manager.mode)
    }
    
    @objc
    func close() {
        dismiss(animated: true)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    static func instance() -> Self {
        return Storyboard.main.instance()
    }
}

// MARK: - Action
extension AudioPlayerController {
    
    /// 播放/暂停
    @IBAction func playAction(_ sender: UIButton) {
        switch manager.player.state {
        case .failed:
            // 失败状态时点击播放按钮 调用重播
            manager.replay()
            
        default:
            if sender.isSelected {
                // 暂停
                manager.player.pause()
                
            } else {
                // 播放
                manager.player.play()
            }
        }
    }
    
    /// 上一个
    @IBAction func prevAction(_ sender: Any) {
        manager.playPrev()
    }
    
    /// 下一个
    @IBAction func nextAction(_ sender: Any) {
        manager.playNext()
    }
    
    /// 打开播放列表
    @IBAction func queueAction(_ sender: Any) {
        let controller = AudioPlayerQueueController.instance()
        controller.show(in: self, animated: true)
    }
    
    /// 切换播放模式
    @IBAction func modeAction(_ sender: Any) {
        switch manager.mode {
        case .sequential:
            manager.mode = .single
            
        case .single:
            manager.mode = .sequential
            
        default:
            break
        }
    }
    
    @objc
    private func sliderTouchBegin(_ sender: UISlider) {
        isDraging = true
    }
    
    @objc
    private func sliderTouchEnd(_ sender: UISlider) {
        isDraging = false
        manager.player.seek(to: .init(time: .init(sender.value)))
    }
    
    @objc
    private func sliderTouchCancel(_ sender: UISlider) {
        isDraging = false
        manager.player.seek(to: .init(time: .init(sender.value)))
    }
    
    @objc
    private func sliderValueChanged(_ sender: UISlider) {
        container.set(current: .init(sender.value))
    }
}

extension AudioPlayerController: AudioPlayerManagerDelegate {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed mode: AudioPlayerManager.PlaybackMode) {
        container.set(playbackMode: mode)
    }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?) {
        if let item = item {
            // 设置界面内容
            container.set(title: item.title, author: item.author)
            container.set(cover: item.cover)
            container.set(switchable: manager.switchable)
            
        } else {
            // 清理界面内容
            container.set(title: nil, author: nil)
            container.set(cover: nil)
            container.set(switchable: (false, false))
        }
        
        // 同步播放器状态
        audioPlayerState(manager.player, state: manager.player.state)
        audioPlayerControlState(manager.player, state: manager.player.control)
        audioPlayerLoadingState(manager.player, state: manager.player.loading)
        audioPlayer(manager.player, updatedDuration: manager.player.duration)
        audioPlayer(manager.player, updatedCurrent: manager.player.current)
        audioPlayer(manager.player, updatedBuffer: manager.player.buffer)
    }
}

extension AudioPlayerController: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .prepare:
            // 准备阶段
            // 重置界面显示
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
            container.slider.isEnabled = false
            container.playButton.isEnabled = false
            
        case .playing:
            // 播放阶段
            container.slider.isEnabled = true
            container.playButton.isEnabled = true
            
        case .stopped:
            // 停止阶段
            // 重置界面显示
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
            container.slider.isEnabled = false
            container.playButton.isEnabled = false
            
        case .finished:
            // 完成阶段
            container.slider.isEnabled = true
            container.playButton.isEnabled = true
            
        case .failed(let error):
            // 失败阶段
            audioPlayer(player, updatedDuration: player.duration)
            audioPlayer(player, updatedCurrent: player.current)
            audioPlayer(player, updatedBuffer: player.buffer)
            container.slider.isEnabled = false
            container.playButton.isEnabled = true
            // 弹出提示
            let alert = UIAlertController(
                title: "Error",
                message: error?.localizedDescription ?? "",
                preferredStyle: .alert
            )
            alert.addAction(.init(title: "Close", style: .cancel))
            alert.addAction(.init(title: "Retry", style: .default, handler: { [weak self] action in
                self?.manager.replay()
            }))
            present(alert, animated: true)
        }
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        switch state {
        case .playing:
            // 播放中
            container.playButton.isSelected = true
            container.resumeAnimation()
            
        case .pausing:
            // 暂停中
            container.playButton.isSelected = false
            container.pauseAnimation()
        }
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        switch state {
        case .began:
            container.playButton.isLoading = true
            
        case .ended:
            container.playButton.isLoading = false
        }
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double) {
        // 更新缓冲进度
        container.set(buffer: progress)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        guard !isDraging else { return }
        // 为拖动Slider时 更新当前时间
        container.set(current: time)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        // 更新总时长 如果time为0 说明实际时长未加载完成. 可先显示Item中的时长 优化体验
        container.set(duration: time > 0 ? time : manager.item?.duration ?? 0)
    }
}
