//
//  AudioPlayerManager.swift
//  Demo
//
//  Created by 李响 on 2022/7/9.
//

import AudioPlayer
import AVFoundation

protocol AudioPlayerManagerDelegate: AnyObject {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed rate: AudioPlayerManager.Rate)
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed mode: AudioPlayerManager.PlaybackMode)
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?)
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed queue: AudioPlayerQueue)

    /// 增强偏好或处理链准备结果变化；实际生效状态还需在进度回调中读取。
    func audioPlayerManagerVolumeBoostChanged(_ manager: AudioPlayerManager)
}

extension AudioPlayerManagerDelegate {
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed rate: AudioPlayerManager.Rate) { }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed mode: AudioPlayerManager.PlaybackMode) { }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed item: AudioPlayerItem?) { }
    
    func audioPlayerManager(_ manager: AudioPlayerManager, changed queue: AudioPlayerQueue) { }

    func audioPlayerManagerVolumeBoostChanged(_ manager: AudioPlayerManager) { }
}

class AudioPlayerManager: NSObject {
    
    static let shared = AudioPlayerManager()
     
    /// 播放器
    let player = AudioPlayer.av.instance()
    /// 增强偏好跨切歌保留；开关变化只更新当前处理器，不重载媒体。
    private(set) var isVolumeBoostEnabled = false
    /// 每首资源独立持有处理器；原音模式也保留 tap，避免切换时重配播放链。
    private(set) var volumeBoost: AudioMixVolumeBoost?
    /// 当前准备的 asset 身份，用于拒绝异步加载的旧结果。
    private var boostAsset: AVURLAsset?
    /// 音轨加载任务；停止、失败、切歌及销毁时取消。
    private var boostPreparation: Task<Void, Never>?
    /// 准备失败或不适用原因；不阻断普通音频播放。
    private var boostUnavailableReason: String?

    /// 区分用户目标和真实 PCM 处理；供页面刷新，不能把开关选中当作生效证据。
    var volumeBoostStatus: String {
        if let reason = boostUnavailableReason { return reason }
        guard let boost = volumeBoost else {
            return boostPreparation == nil ? "等待播放资源" : "正在准备增强；当前原音播放"
        }
        if boost.hasPreparedFormat && !boost.isSupported { return "当前 PCM 格式不支持增强，保持原音" }
        guard boost.processedFrames > 0, boost.isSupported else { return "等待 PCM 回调，尚未确认增强可用" }
        return isVolumeBoostEnabled ? "2× 目标已设置 · PCM 处理已运行" : "原始音量 1× · PCM 处理已运行"
    }

    /// 主线程修改偏好；暂停时不触发播放，准备完成后读取最新值。
    func setVolumeBoostEnabled(_ enabled: Bool) {
        isVolumeBoostEnabled = enabled
        volumeBoost?.setEnabled(enabled)
        delegate { $0.audioPlayerManagerVolumeBoostChanged(self) }
    }

    /// 播放模式 默认顺序播放
    var mode: PlaybackMode = .sequential {
        didSet {
            player.isLoop = mode == .single
            delegate { $0.audioPlayerManager(self, changed: mode) }
        }
    }
    /// 播放倍速 默认1.0
    var rate: Rate = ._1_0 {
        didSet {
            player.rate = rate.rawValue
            delegate { $0.audioPlayerManager(self, changed: rate) }
        }
    }
    /// 播放项队列
    private(set) var queue: AudioPlayerQueue = .init([])
    /// 当前播放项
    private(set) var item: AudioPlayerItem?
    /// 可切换状态 (prev: 上一首, next: 下一首)
    private(set) var switchable: (prev: Bool, next: Bool) = (false, false)
    
    private lazy var remote = RemoteControl(player)
    
    var delegates: [AudioPlayerDelegateBridge<AnyObject>] = []
    
    private var lastUpdateItemStateTime: TimeInterval = 0
    
    override init() {
        super.init()
        setup()
        setupNotification()
    }
    
    deinit {
        boostPreparation?.cancel()
    }

    /// 播放队列的项目
    func play(_ item: AudioPlayerItem, for queue: AudioPlayerQueue) {
        // 更新当前队列
        update(queue)
        // 更新当前Item
        update(item)
    }
    
    /// 播放上一项
    func playPrev() {
        guard let item = item else { return }
        guard let temp = queue.prev(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    /// 播放下一项
    func playNext() {
        guard let item = item else { return }
        guard let temp = queue.next(of: item) else { return }
        // 更新当前Item
        update(temp)
    }
    
    /// 重播当前项
    func replay() {
        guard let item = item else { return }
        update(item)
    }
    
    /// 清空
    func clear() {
        update(.init([]))
        update(.none)
    }
}

extension AudioPlayerManager {
    
    private func setup() {
        // 设置播放倍速
        player.rate = rate.rawValue
        // 允许后台播放
        player.allowedBackgroundPlayback = true
        // 添加播放器代理
        player.add(delegate: self)
        
        // 设置远程控制 (上一首/下一首) 的回调
        remote.playPrev = { [weak self] in
            self?.playPrev()
        }
        remote.playNext = { [weak self] in
            self?.playNext()
        }
    }
    
    private func setupNotification() {
        /// 会话线路变更通知
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            guard
                let info = sender.userInfo,
                let reason = info[AVAudioSessionRouteChangeReasonKey] as? Int else {
                return
            }
            switch AVAudioSession.RouteChangeReason(rawValue: UInt(reason)) {
            case .oldDeviceUnavailable?:
                DispatchQueue.main.async {
                    // 暂停播放
                    self.player.pause()
                }
                
            default: break
            }
        }
        /// 应用即将终止通知
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            // 应用终止时 存储Item状态
            self.updateItemState()
        }
    }
}

extension AudioPlayerManager {
    
    private func update(_ queue: AudioPlayerQueue) {
        self.queue = queue
        
        delegate { $0.audioPlayerManager(self, changed: queue) }
    }
    
    private func update(_ item: AudioPlayerItem?) {
        // 旧音轨加载不得跨切歌提交；先清理身份，再建立新资源。
        cancelVolumeBoost()
        // 置空当前Item, 防止状态被错误更新
        self.item = nil
        
        if let item = item {
            // 准备播放资源
            let asset = AVURLAsset(url: item.resource)
            boostAsset = asset
            player.prepare(resource: asset)
            // 处理Item状态
            if let state = item.state {
                switch state {
                case .record(let time):
                    // 自动跳转到上一次播放的进度
                    player.seek(to: .init(time: time))
                    
                default:
                    break
                }
            }
            // 设置可切换状态
            switchable = (queue.prev(of: item), queue.next(of: item))
            
            // 设置远程控制
            remote.set(
                title: item.title,
                artist: item.author,
                cover: nil,
                url: item.resource
            )
            remote.set(switchable: switchable)
            
            // 设置当前Item
            self.item = item
            prepareVolumeBoost(for: asset)
            
        } else {
            // 播放器停止
            player.stop()
            // 设置可切换状态
            switchable = (false, false)
        }
        
        delegate { $0.audioPlayerManager(self, changed: item) }
    }
    
    /// 与原播放并行加载音轨；保留准备阶段 pause、seek 和历史恢复的既有时序。
    private func prepareVolumeBoost(for asset: AVURLAsset) {
        // prepare 的同步代理可能已停止或切换资源，不再为失效的 asset 创建任务。
        guard boostAsset === asset else { return }
        // HLS 不属于此示例的增强路径，不影响它使用原音播放。
        guard asset.url.pathExtension.lowercased() != "m3u8" else {
            boostUnavailableReason = "HLS 不支持此增强示例，保持原音"
            return
        }
        boostPreparation = Task { @MainActor [weak self] in
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard !Task.isCancelled, let self = self, self.boostAsset === asset else { return }
                let boost = try AudioMixVolumeBoost(tracks: tracks)
                boost.setEnabled(self.isVolumeBoostEnabled)
                // 只绑定当前 item；失败时保持原有播放，不回退重建资源。
                let applied = (self.player as? AVAudioMixControlling)?.update(audioMix: boost.mix, for: asset) == true
                self.volumeBoost = applied ? boost : nil
                self.boostUnavailableReason = applied ? nil : "处理链未安装，保持原音"
                self.boostPreparation = nil
                self.delegate { $0.audioPlayerManagerVolumeBoostChanged(self) }
            } catch {
                guard !Task.isCancelled, let self = self, self.boostAsset === asset else { return }
                self.boostPreparation = nil
                self.boostUnavailableReason = "增强准备失败，保持原音：\(error.localizedDescription)"
                self.delegate { $0.audioPlayerManagerVolumeBoostChanged(self) }
            }
        }
    }

    /// 取消任务并清理外部持有状态；tap 的最终释放由 AVPlayerItem 与系统共同决定。
    private func cancelVolumeBoost() {
        boostPreparation?.cancel()
        boostPreparation = nil
        boostAsset = nil
        volumeBoost = nil
        boostUnavailableReason = nil
    }

    private func updateItemState() {
        switch player.state {
        case .playing:
            item?.state = .record(player.current)
            
        case .finished:
            item?.state = .played
            
        case .failed where item?.state == nil:
            item?.state = .failed
            
        default:
            break
        }
    }
    
    private func playRandom() {
        guard let item = item else { return }
        update(queue.random(of: item))
    }
}

extension AudioPlayerManager: AudioPlayerDelegate {
    
    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        
        updateItemState()
        
        switch state {
        case .prepare:
            // 准备阶段
            
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
            // 播放阶段
            break
            
        case .stopped:
            cancelVolumeBoost()
            // 停止阶段
            
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
            // 完成阶段
            
            // 根据播放模式设置
            switch mode {
            case .random:
                // 播放随机项
                playRandom()
                
            case .sequential:
                // 播放下一首
                playNext()
                
            default:
                break
            }
            
        case .failed(let error):
            cancelVolumeBoost()
            // 失败阶段
            print(error?.localizedDescription ?? "")
        }
    }
    
    func audioPlayerControlState(_ player: AudioPlayerable, state: AudioPlayer.ControlState) {
        updateItemState()
    }
    
    func audioPlayerLoadingState(_ player: AudioPlayerable, state: AudioPlayer.LoadingState) {
        updateItemState()
    }
    
    func audioPlayer(_ player: AudioPlayerable, seekBegan: AudioPlayer.Seek) {
        updateItemState()
    }
    
    func audioPlayer(_ player: AudioPlayerable, seekEnded: AudioPlayer.Seek) {
        updateItemState()
    }
    
    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        // 控制一秒间隔更新一次状态
        guard (lastUpdateItemStateTime - time).magnitude > 1 else {
            return
        }
        lastUpdateItemStateTime = time
        updateItemState()
    }
}

extension AudioPlayerManager: AudioPlayerDelegates {
    
    typealias Element = AudioPlayerManagerDelegate
}

extension AudioPlayerManager {
    
    enum PlaybackMode {
        // 单曲循环
        case single
        // 随机播放
        case random
        // 顺序播放
        case sequential
    }
    
    enum Rate: Double {
        case _0_5   = 0.5
        case _0_8   = 0.8
        case _1_0   = 1.0
        case _1_1   = 1.1
        case _1_2   = 1.2
        case _1_3   = 1.3
        case _1_4   = 1.4
        case _1_5   = 1.5
        case _1_6   = 1.6
        case _1_7   = 1.7
        case _1_8   = 1.8
        case _1_9   = 1.9
        case _2_0   = 2.0
        case _2_1   = 2.1
        case _2_2   = 2.2
        case _2_3   = 2.3
        case _2_4   = 2.4
        case _2_5   = 2.5
        case _2_6   = 2.6
        case _2_7   = 2.7
        case _2_8   = 2.8
        case _2_9   = 2.9
        case _3_0   = 3.0
    }
}
