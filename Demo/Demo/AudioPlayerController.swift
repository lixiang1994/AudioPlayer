//
//  AudioPlayerController.swift
//  Demo
//
//  Created by 李响 on 2022/7/8.
//

import UIKit
import AudioPlayer
import AVFoundation

class AudioPlayerController: ViewController<AudioPlayerView> {

    enum PlayMode {
        // 单曲播放
        case one
        // 顺序播放
        case loop
    }
    
    private let player = AudioPlayer.av.instance()
    private lazy var remote = AudioPlayerRemote(player)
    
    private var isDraging = false
    
    private var playMode: PlayMode = .loop {
        didSet {
            container.change(play: playMode)
            player.isLoop = playMode == .one
        }
    }
    
    var queue: AudioPlayerQueue?
    var item: AudioPlayerQueue.Item?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
        setupNotification()
    }
    
    private func setup() {
        player.allowBackgroundPlayback = false
        player.add(delegate: self)
        player.rate = 1.0
        
        container.startAnmiation()
        container.pauseAnimation()
        
        playMode = .loop
        
        container.slider.addTarget(self, action: #selector(sliderTouchBegin), for: .touchDown)
        container.slider.addTarget(self, action: #selector(sliderTouchEnd), for: [.touchUpInside, .touchUpOutside])
        container.slider.addTarget(self, action: #selector(sliderTouchCancel), for: .touchCancel)
        container.slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    }
    
    private func setupNotification() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            
        }
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
        if sender.isSelected {
            // 暂停
            player.pause()
            
        } else {
            // 播放
            player.play()
        }
    }
    
    /// 上一个
    @IBAction func prevAction(_ sender: Any) {
        playPrev()
    }
    
    /// 下一个
    @IBAction func nextAction(_ sender: Any) {
        playNext()
    }
    
    /// 打开播放列表
    @IBAction func queueAction(_ sender: Any) {
        
    }
    
    /// 切换播放模式
    @IBAction func modeAction(_ sender: Any) {
        switch playMode {
        case .one:
            playMode = .loop
            
        case .loop:
            playMode = .one
        }
    }
    
    @objc
    private func sliderTouchBegin(_ sender: UISlider) {
        isDraging = true
    }
    
    @objc
    private func sliderTouchEnd(_ sender: UISlider) {
        isDraging = false
        player.seek(to: .init(time: .init(sender.value)))
    }
    
    @objc
    private func sliderTouchCancel(_ sender: UISlider) {
        isDraging = false
        player.seek(to: .init(time: .init(sender.value)))
    }
    
    @objc
    private func sliderValueChanged(_ sender: UISlider) {
        container.set(current: .init(sender.value))
    }
}

extension AudioPlayerController {
    
    /// 播放队列的项目
    func play(_ item: AudioPlayerQueue.Item, for queue: AudioPlayerQueue) {
        self.item = item
        self.queue = queue
        update()
    }
}

extension AudioPlayerController {
    
    private func update() {
        if let item = item, let queue = queue {
            container.set(title: item.title, author: item.author)
            container.set(cover: item.cover)
            container.set(switchable: (queue.prev(of: item), queue.next(of: item)))
            player.prepare(url: item.resource)
            remote.set(
                title: item.title,
                artist: item.author,
                thumb: UIImage(named: "audio_player_cover")!,
                url: item.resource
            )
            
        } else {
            container.set(title: nil, author: nil)
            container.set(cover: nil)
            container.set(switchable: (false, false))
        }
    }
    
    private func playNext() {
        guard let item = item else { return }
        self.item = queue?.next(of: item)
        update()
    }
    
    private func playPrev() {
        guard let item = item else { return }
        self.item = queue?.prev(of: item)
        update()
    }
}

extension AudioPlayerController: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .prepare:
            // 准备播放
            container.set(current: 0)
            container.playButton.isEnabled = false
            
            // 设置音频会话模式
            UIApplication.shared.beginReceivingRemoteControlEvents()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话创建失败")
            }
            
        case .playing:
            // 播放中
            container.playButton.isEnabled = true
            
        case .stopped:
            // 停止
            container.set(current: 0)
            container.playButton.isEnabled = false
            
            // 设置音频会话模式
            UIApplication.shared.endReceivingRemoteControlEvents()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话释放失败")
            }
            
        case .finished:
            // 播放完毕
            if playMode == .loop {
                // 下一曲
                playNext()
            }
            
        case .failure(let error):
            // 播放失败
            print(error?.localizedDescription ?? "")
        }
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        switch state {
        case .playing:
            container.playButton.isSelected = true
            container.resumeAnimation()
            
        case .pausing:
            container.playButton.isSelected = false
            container.pauseAnimation()
        }
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedDuration time: Double) {
        container.set(duration: time)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedBuffer progress: Double) {
        container.set(buffer: progress)
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        guard !isDraging else { return }
        
        container.set(current: time)
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        // UI效果待优化
        switch state {
        case .began:
            container.playButton.loading.start()
            
        case .ended:
            container.playButton.loading.stop()
        }
    }
}
