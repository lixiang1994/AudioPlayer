# AudioPlayer

轻量的 Swift 音频播放器封装，基于 AVPlayer 提供统一的播放控制、状态通知、后台播放策略和锁屏控制，适合播客、音乐与有声内容应用。

通过 `AudioPlayerable` 协议隔离业务与播放后端；使用默认 AVPlayer 后端即可播放本地文件和网络音频，也可以实现自己的后端。

[特性](#特性) · [兼容性](#兼容性) · [安装](#安装) · [快速开始](#快速开始) · [音频混合与音量增强](#音频混合与音量增强) · [Demo](#demo) · [测试](#测试)

## 特性

- **播放控制**：准备、播放、暂停、停止、寻时、倍速、静音、音量与单曲循环。
- **资源支持**：接收 `URL`、`AVURLAsset`，或携带 `AVAudioMix` 的 `AVAudioPlayerResource`；解码能力取决于系统 AVFoundation。
- **状态通知**：通过弱引用多播代理观察资源状态、播放控制、缓冲、时长和进度。
- **生命周期处理**：隔离切资源后的旧回调，连续 seek 以最后一次请求为准，处理音频中断、路由变化和媒体服务重置。
- **后台与锁屏**：提供后台播放策略、Now Playing 信息同步和基础播放／暂停远程命令。
- **外部音频处理**：支持传入和动态更新 `AVAudioMix`，可结合外部 `MTAudioProcessingTap` 实现 PCM 处理。
- **按需集成**：Core 协议层与 AVPlayer 后端分离，库本身无第三方运行时依赖。

播放列表、播放历史、上一首／下一首和 UI 属于业务层；仓库 Demo 提供了相应示例。音量增强算法也位于 Demo 中，不是播放器默认开启的功能。

## 环境要求

| 项目 | 配置 |
| --- | --- |
| iOS | podspec 声明 iOS 12.0+ |
| Swift | podspec 声明 Swift 5.2；本文异步音轨加载示例需要 Swift 5.5+、iOS 15+ |
| 安装方式 | CocoaPods |
| iPhone Demo | iOS 17.6+，打开 `Demo/Demo.xcworkspace` |

本文以 **iOS AVPlayer 后端**为主。最低系统声明不等于所有系统版本均已回归；最近真机验证环境为 iPhone 16e / iOS 27.0.1。仓库包含旧 watchOS 示例及 podspec 配置，但不代表默认 AVPlayer 后端可直接用于 watchOS；旧 WatchKit Extension 示例需迁移后才能在 Xcode 27 运行。

## 兼容性

以下说明针对默认 **AVPlayer 后端**。AudioPlayer 不内置 FFmpeg 或自定义解码器，实际可播放性由系统版本、容器、编码、编码参数与资源服务共同决定。文件后缀相同，不代表内部编码相同；下表中的“系统支持”也不代表项目已对所有编码组合完成测试。

### 音频格式

| 格式 / 编码 | 常见容器或后缀 | 兼容说明 | 项目验证 |
| --- | --- | --- | --- |
| MP3 | `.mp3` | 系统常见支持格式，适合本地与 HTTP 文件播放 | 本地播放及向后 seek；HTTP 分块供数、卡顿与恢复 |
| AAC | `.m4a`、`.mp4`、ADTS `.aac` | 系统支持常见 AAC 编码；M4A/MP4 是容器，具体 AAC profile 仍需验证 | 已验证 AAC 编码的 M4A，本地与 HTTP；未单独验证裸 ADTS AAC |
| Linear PCM | `.wav`、`.aif` / `.aiff`、`.caf` | 系统支持常见 PCM 组合；位深、字节序及容器需匹配 | 已验证本地与 HTTP WAV；AIFF/CAF 未回归 |
| Apple Lossless（ALAC） | `.m4a`、`.caf` | 系统支持的无损编码；M4A 也可能装载 AAC | 未回归 |
| FLAC | `.flac` | 目标 iOS / AVFoundation 的实际支持需用样本确认，不能仅凭系统其他播放器可播放来判断 | 未回归，不列为本库已验证格式 |
| Vorbis / Opus | `.ogg`、`.opus`、WebM 等 | 不提供跨版本的默认后端兼容承诺；编码与容器组合需单独确认 | 未回归，库不提供解码回退 |
| WMA / APE 等 | `.wma`、`.ape` | 不属于本库承诺的原生播放范围，需要转码或其他解码后端 | 未支持验证 |

HLS（`.m3u8`）是传输与分段播放方案，不是音频编码；分片中的音频仍需符合系统支持的编码要求。

### 本地与网络资源

| 资源类型 | 使用方式与边界 | 项目验证 |
| --- | --- | --- |
| App Bundle 文件 | 从 `Bundle` 获取文件 URL，传入 `prepare(resource:)` | 已验证 |
| 沙盒文件 / 已下载文件 | 使用 `URL(fileURLWithPath:)`；调用方确保文件存在且可读 | 已验证临时本地文件；无自动下载管理 |
| 外部导入文件 | 调用方处理文件访问权限、security-scoped 访问或先复制到沙盒 | 未专项验证权限链路 |
| HTTP / HTTPS 音频文件 | 直接传入 URL，由 AVPlayer 加载与缓冲，可边下载边播放；推荐 HTTPS | 已验证本机 HTTP WAV、AAC/M4A、MP3；未覆盖公网 TLS / 证书链路 |
| HLS 点播 | 传入播放列表 URL，由系统请求列表与分片 | 已验证 HTTP HLS VOD 播放、seek 后推进；不代表所有分片或加密组合兼容 |
| HLS 直播 / DVR | 系统具备相关播放能力；直播可能没有固定时长，seek 受可寻时窗口限制 | 尚未专项适配与验证，不能照搬点播的进度条与循环逻辑 |
| ICY / Shoutcast、RTSP、RTMP 等 | 不提供专用协议、流元数据解析或解码扩展 | 不作兼容承诺；普通 MP3 HTTP 测试不能替代这些协议测试 |
| DRM / FairPlay 内容 | 需要宿主提供授权与密钥处理；库没有内置 DRM 接入流程 | 未集成验证 |

网络资源还需注意：

- HTTP 明文访问受 App Transport Security（ATS）限制；宿主按实际域名需求配置，优先使用 HTTPS。
- 快速准备及 seek 取决于服务器响应、Range 支持、媒体索引与系统缓冲；`preferredBufferDuration` 不代表下载完成或固定缓存大小。
- 已测试重定向、Range、404/401、慢响应和断流后显式重试；库没有业务层鉴权刷新或无限自动重试。需要特殊加载行为时使用 `AVURLAsset` 及系统公开的加载机制，授权由调用方负责。
- 网络缓冲不是持久离线缓存。库不提供下载器、磁盘缓存或 HLS 离线下载管理，也不接收 `Data` / 自定义 PCM 流作为直接播放资源。

```swift
// 以下操作在主线程执行；player 为业务持续持有的实例。
if let localURL = Bundle.main.url(forResource: "episode", withExtension: "mp3") {
    player.prepare(resource: localURL)
}

// networkURL 由业务提供，可为 HTTPS 音频文件或支持的 HLS 播放列表地址。
player.prepare(resource: networkURL)

// 需要保留 asset 身份或加载配置时，也可以直接传入 AVURLAsset。
let asset = AVURLAsset(url: networkURL)
player.prepare(resource: asset)
```

## 安装

### CocoaPods

在应用的 `Podfile` 中添加：

```ruby
platform :ios, '12.0'

target 'YourApp' do
  pod 'AudioPlayer'
end
```

执行 `pod install`，随后打开应用的 `.xcworkspace`。

默认包含 `Core` 与 `AVPlayer`。如果只需要协议层并自行实现播放后端：

```ruby
pod 'AudioPlayer/Core'
```

### 使用当前源码

本文描述当前源码 API，包含新增的 `AVAudioPlayerResource` 和 `AVAudioMixControlling`；公开 CocoaPods 版本可能尚未包含这些接口。需要体验当前实现时，使用本地路径集成：

```ruby
pod 'AudioPlayer', :path => '../AudioPlayer'
```

路径相对于应用 `Podfile` 所在目录。仓库目前没有 `Package.swift`，尚未提供 Swift Package Manager 集成配置。

## 快速开始

播放器的创建、控制、属性访问、代理增删及销毁都应在**主线程**完成，代理和 seek completion 也在主线程回调。业务层需要持续持有播放器；代理为弱引用，也需要由业务层持有。

```swift
import Foundation
import AudioPlayer

final class PlaybackController: NSObject, AudioPlayerDelegate {
    // 使用独立实例；由业务对象持有，避免局部变量释放后停止播放。
    let player: AudioPlayerable

    override init() {
        var configuration = AudioPlayerConfiguration()
        configuration.isAutoplay = true
        configuration.preferredBufferDuration = 5
        configuration.currentTimeCallbackPeriodicInterval = 10
        player = AudioPlayer.av.instance(configuration)
        super.init()
        player.add(delegate: self)
    }

    func open(_ url: URL) {
        // 本地文件使用 file URL，网络资源使用可访问的 HTTPS URL。
        // 默认自动播放：资源就绪后开始播放，无需再次调用 play。
        player.prepare(resource: url)
    }

    func audioPlayerState(_ player: AudioPlayerable, state: AudioPlayer.State) {
        switch state {
        case .prepare:
            print("正在准备")
        case .playing:
            print("资源已就绪")
        case .stopped:
            print("已停止")
        case .finished:
            print("播放结束")
        case .failed(let error):
            print("播放失败：", error as Any)
        }
    }

    func audioPlayer(_ player: AudioPlayerable, updatedCurrent time: Double) {
        print("进度：", time, "/", player.duration)
    }
}
```

将 `PlaybackController` 保存为页面或业务管理器的属性，再在主线程调用 `open(_:)`。也可以通过 `AudioPlayer.av.shared` 获取共享实例；对共享实例的操作会影响所有使用方。

### 配置

| 配置项 | 默认值 | 含义 |
| --- | --- | --- |
| `isAutoplay` | `true` | 准备完成后是否自动播放 |
| `preferredBufferDuration` | `0` | 期望前向缓冲时长，单位秒；0 交给系统决定 |
| `currentTimeCallbackPeriodicInterval` | `10` | 每秒进度回调次数，**不是回调间隔秒数** |

配置在创建实例时传入。设置 `isAutoplay = false` 后，由业务在需要时调用 `play()`。

## 播放控制

以下示例中的 `player` 为持续持有的 `AudioPlayerable` 实例：

```swift
player.play()
player.pause()
player.rate = 1.5
player.volume = 0.8
player.isMuted = false
player.isLoop = true

player.seek(to: .init(time: 60) { finished in
    // false 也可能表示请求被覆盖、停止或切资源取消，不能当作已到达目标。
    if finished {
        print("实际位置：", player.current)
    }
})

// 停止并释放当前资源；再次播放需要重新 prepare。
player.stop()
```

`volume` 使用 0…1 范围，设置为 2 不能实现两倍音量增强。倍速能否实际生效取决于媒体与系统能力。暂停期间修改倍速不会启动播放；非循环资源播放结束后调用 `play()` 会从头重播。

准备期间可以提交 seek；连续请求以最后一次为准。被覆盖或取消的请求会以 `false` 完成一次。时间属性 `current`、`duration` 的单位为秒，`buffer` 为 0…1 的缓冲进度。

### 正确理解状态

| 属性 | 含义 |
| --- | --- |
| `state` | 资源生命周期：`prepare`、`playing`、`stopped`、`finished`、`failed` |
| `control` | 播放控制状态：`playing` 或 `pausing` |
| `loading` | 等待媒体数据：`began` 或 `ended` |

**`state == .playing` 的语义是资源已就绪，并不表示正在出声。** 暂停后仍保持该资源状态；UI 应结合 `state`、`control` 和 `loading` 展示播放、暂停与缓冲状态。

`AudioPlayerDelegate` 的方法都有默认空实现，可仅实现需要的回调。除快速开始中的回调外，还可监听 `audioPlayerControlState`、`audioPlayerLoadingState`、缓冲与时长更新、seek 开始与结束。调用 `remove(delegate:)` 可解除订阅。

## 后台播放与锁屏控制

宿主应用负责配置 `AVAudioSession`。在合适的业务时机处理音频会话配置及错误：

```swift
import AVFoundation

do {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
} catch {
    print("音频会话配置失败：", error)
}
```

在应用 Target 的 **Signing & Capabilities → Background Modes** 中启用 **Audio, AirPlay, and Picture in Picture**（对应 `UIBackgroundModes` 的 `audio`）。播放器的 `allowedBackgroundPlayback` 默认为 `true`，仍需宿主完成以上系统配置。

设置 `player.allowedBackgroundPlayback = false` 时，进入后台会暂停，回到前台按保留的播放意图恢复；用户主动暂停后不会自动恢复。

使用锁屏控制时，持续持有一个 `AudioPlayerRemoteControl`：

```swift
// 保存为业务对象的属性；初始化后自动注册基础远程命令。
let remoteControl = AudioPlayerRemoteControl(player)

// 在资源就绪后设置标题、作者和封面，避免被 prepare 时的清理覆盖。
remoteControl.set(
    title: "节目标题",
    artist: "作者",
    cover: nil,
    url: mediaURL
)
```

上面的 `mediaURL` 是当前资源 URL。可在 `audioPlayerState(_:state:)` 的 `.playing` 分支中设置元信息。该对象会同步进度、时长与倍速，默认注册播放／暂停命令；上一首、下一首等业务命令需自行扩展。远程命令及 Now Playing 属于系统全局资源，应只让当前主播放器接管。

## 音频混合与音量增强

### mix / tap 兼容范围

`AVAudioMix` 提供音轨音量包络等混合参数；`MTAudioProcessingTap` 则在系统交付 PCM 时执行自定义处理。**能解码播放、能设置 mix、实际运行 tap 是三件不同的事。** `setVolume` 的标准范围是 0…1，2× 增强需要类似 Demo 的 PCM 处理器。

| 场景 | AVAudioMix / tap 说明 | 当前验证与建议 |
| --- | --- | --- |
| 本地、未受保护的文件资源 | 主要适用路径；参数的 track ID 必须对应当前 asset 的音轨 | 已验证本地 mix 绑定、替换、移除及播放状态；Demo 已验证实际 PCM 1×/2× 与限幅 |
| HTTP / HTTPS 普通音频文件 | 网络 URL 不等于 HLS；能播放不保证该资源路径会应用 mix 或调用 tap | 已增加本机 HTTP WAV、AAC/M4A、MP3 的真实 tap 与 1→2→1 增益回归；仅代表这些样本，不覆盖公网 HTTPS、所有编码参数或输出路由 |
| HLS 点播 / 直播 | 不作为本库 AVAudioMix / tap 增强的受支持路径；不能依赖给 HLS item 设置 mix 来获得处理效果 | 已通过的 HLS 测试仅验证普通播放，不包含 mix 或 tap；应保留原音播放方案 |
| 受保护 / DRM 内容 | 不承诺可取得用于外部处理的 PCM | 未验证，不应据此设计增强功能 |
| 扬声器 / 有线 / 蓝牙 / AirPlay | 路由可能改变输出格式、缓冲或播放处理路径；远程播放尤其不能假定 tap 会在本机执行 | 当前验证不能替代蓝牙 / AirPlay 兼容测试；需要实际检查处理回调及效果 |
| 播放中替换 mix | `update(audioMix:for:)` 保持当前 item、进度及播放意图，系统仍可能重配置处理链 | 已验证同 item、暂停保留、nil 移除及错误 asset 拒绝；不保证采样级无间断 |
| 播放中切换增强参数 | 复用已安装的 tap，仅发布线程安全的增益目标 | Demo 已验证连续切换与暂停保留，是原音 / 2× 开关的推荐方式 |

这些系统 API 早于本库声明的 iOS 12 最低版本；README 的 `loadTracks(withMediaType:)` 异步示例需要 iOS 15+，不表示 mix 功能本身必须 iOS 15。当前新接口仍以源码集成为准，且没有完成 iOS 12 起所有系统版本的 mix 回归。系统层边界可参考 Apple 的 [AVAudioMix](https://developer.apple.com/documentation/avfoundation/avaudiomix)、[MTAudioProcessingTap](https://developer.apple.com/documentation/mediatoolbox/mtaudioprocessingtap) 与 [QA1716：AVPlayer 音量控制](https://developer.apple.com/library/archive/qa/qa1716/_index.html)。

Demo 处理器仅处理系统协商出的**原生字节序、紧密排列的 Float32 / 有符号 Int16 / Int32 PCM**；其他格式保持原样并报告未支持。这是解码后的 PCM 格式限制，不是 MP3/AAC 文件后缀白名单。当前测试没有穷举所有 PCM 格式；集成时需检查实际格式与处理帧计数，不能仅凭 `update` 返回成功就显示“增强已生效”。

### 为资源传入 AVAudioMix

外部加载音轨，使用**同一个 asset 的音轨**构建参数，然后将 asset 与 mix 一起传入播放器。下面的辅助方法需要 Swift 5.5+、iOS 15+；旧系统应使用对应的异步加载 API。

```swift
import AVFoundation
import AudioPlayer

@available(iOS 15.0, *)
@MainActor
func prepareWithMix(player: AudioPlayerable, asset: AVURLAsset) async throws {
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let mix = AVMutableAudioMix()
    mix.inputParameters = tracks.map { track in
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolume(0.5, at: .zero)
        return parameters
    }

    player.prepare(resource: AVAudioPlayerResource(asset: asset, audioMix: mix))
}
```

`AVAudioPlayerResource` 初始化时复制 mix 配置；后续修改原 `AVMutableAudioMix` 不会自动更新当前播放。传入普通 `URL`、`AVURLAsset` 或 nil mix 时，不会继承上一资源的处理。

### 播放中更新 mix

```swift
if let mixing = player as? AVAudioMixControlling {
    // asset 必须是当前资源使用的同一个实例，而不只是 URL 相同。
    let applied = mixing.update(audioMix: newMix, for: asset)
    print("配置是否提交：", applied)

    // nil 移除当前 mix。
    mixing.update(audioMix: nil, for: asset)
}
```

这里的 `newMix` 是针对当前 `asset` 构建的新配置。接口在主线程同步提交，不重建 item、不 seek，也不改变播放／暂停意图。没有当前资源或 asset 实例不匹配时返回 `false`，不会将更新缓存到下一首。

`mixing.audioMix` 表示当前 item 的配置，`player.resource` 中保存的仍是准备时快照。如果复用同一 asset 实例多次准备，调用方需取消旧的异步加载任务，避免过期结果更新当前播放。

### 原始音量 / 2× 增强

类似播客应用的播放中增强开关，建议**准备时安装一次 mix 和 tap，切换时只更新处理器的增益参数**。Demo 使用 `MTAudioProcessingTap` 处理 PCM，原音与增强共用同一个 item、mix 和 tap，切换不从头播放，暂停时切换也保持暂停。

Demo 实现包含 1×／2× 增益、块内平滑和 [-1, 1] 限幅；实时 C 回调通过无锁原子读取参数，不分配、不加锁。目标在下一次 tap 处理时生效，已经处理并排队的音频仍可能带来听感延迟。2× 指振幅增益，未削波时约 +6 dB，不等于主观响度翻倍；限幅可能产生削波失真。

外部处理器负责 DSP、实时线程安全和状态释放。mix 的复制不会复制或隔离 tap 内部状态。`update` 返回 `true` 仅表示配置已提交；任意 mix 替换可能触发系统音频链重配置，无法保证采样级无间断。HLS、受保护内容及不同输出路由能否使用 tap，需要分别验证，普通播放成功不代表 PCM 处理可用。

参考实现：[试听页面](Demo/Demo/Controller/AudioMixExampleController.swift)、[mix/tap 生命周期](Demo/Demo/AudioProcessing/AudioMixVolumeBoost.swift)、[实时 PCM 处理](Demo/Demo/AudioProcessing/AudioMixVolumeBoost.c)。

## Demo

```sh
git clone https://github.com/lixiang1994/AudioPlayer.git
cd AudioPlayer/Demo
pod install --no-repo-update
open Demo.xcworkspace
```

在 Xcode 中选择 **Demo** scheme 和 iPhone 模拟器或真机，再执行 Run。真机运行需配置自己的签名 Team，App 与 DemoTests 使用一致的 Team。根目录 `AudioPlayer.xcodeproj` 构建的是库；日常体验请打开 Demo workspace。

Demo 包含播放列表、播放历史、播放模式、倍速及锁屏控制等业务示例。原播放页新增 **音量增强 2×** 开关，作用于列表当前播放资源（原列表使用网络 URL）。处理器就绪后切换仅修改增益，保留进度、暂停状态与倍速，偏好跨切歌保留；加载失败或未确认 PCM 回调时显示实际状态，普通播放继续。首次安装处理链可能经过系统重配置，不能保证采样级无间断。

列表右上角 **AudioMix → AudioMix 案例** 使用内置本地 WAV《夜曲》，无需网络，提供以下案例：

| 案例 | 演示能力 |
| --- | --- |
| 增强 | 复用 tap，切换原始 1× / PCM 2× 增益 |
| 无 mix | 动态移除 mix，恢复系统原音 |
| 25% | 用音轨参数设置固定音量，不改变 `player.volume` |
| 淡入 | 从选择位置起，用 5 秒媒体时间由静音渐变到原音 |
| 淡出/恢复 | 用 2 秒淡出到静音，再用 2 秒恢复原音 |

所有案例在当前 item 上更新；暂停时切换保持暂停，包络按媒体时间执行，seek 会跳到包络对应位置。试听步骤：

1. 点击“播放 / 继续”，播放几秒。
2. 切换“原始音量 1× / 音量增强 2×”，观察进度持续推进。
3. 暂停后切换增强，确认仍保留暂停位置，再继续播放。
4. 拖动进度、停止或退出，检查寻时与资源清理行为。

试听使用独立播放器；进入前暂停列表播放，返回后不自动恢复列表。旧 Watch 示例在 Xcode 27 下的限制及工程说明见 [Demo 运行与测试说明](Demo/Tests/README.md)。

## 测试

完成 Demo 依赖安装后，可在 Xcode 中选择 Demo scheme 执行 **Product → Test**，或在仓库根目录执行：

```sh
xcodebuild test \
  -workspace Demo/Demo.xcworkspace \
  -scheme Demo \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

将 `SIMULATOR_UUID` 替换为 `xcrun simctl list devices available` 中的设备 ID。测试使用全局音频会话与 Now Playing，请保持串行执行。

当前 Demo scheme 包含 **88 项测试**，覆盖播放生命周期、seek 时序与取消、HTTP/Range/断流恢复、音频会话策略、远程控制、audioMix 和 Demo 增强链路。最近一次 iPhone 16e / iOS 27.0.1 真机全量回归 **88 项通过、0 失败**；结果见下方链接的最新记录。网络测试使用本机 HTTP 服务，不依赖外网。

系统通知测试不等于真实来电或蓝牙设备测试。来电、蓝牙、AirPlay、实际锁屏、蜂窝／Wi-Fi 切换、多系统版本及数小时稳定性仍需补充验证；独立 `DevicePlayback` UI scheme 也不计入上述通过数量。完整范围、运行步骤与证据见 [测试说明](Demo/Tests/README.md) 和 [真机验证记录](Demo/Tests/DEVICE-VALIDATION.md)。

## 贡献

欢迎提交 Issue 或 Pull Request。报告问题时请提供系统与 Xcode 版本、资源类型、复现步骤及相关日志。修改播放器时请保持主线程访问约定和既有状态语义，并为异步取消、切资源或生命周期变化补充回归验证。

## License

AudioPlayer 使用 [MIT License](LICENSE)，Copyright © 2022 LEE。
