# Demo 测试

测试入口为 `Demo/Demo.xcworkspace` 的共享 `Demo` scheme，测试 target 为 `DemoTests`。测试链接实际 CocoaPods AudioPlayer 模块，并在 Demo App 中运行；不另外复制播放器实现。

## 运行

先在 `Demo` 目录执行：

```sh
pod install --no-repo-update
```

在 Xcode 中打开 workspace，选择已启动的 iPhone 模拟器，运行 Product → Test。也可以使用命令行；将 `SIMULATOR_UUID` 替换为 `xcrun simctl list devices available` 中的设备 ID：

```sh
xcodebuild test \
  -workspace Demo/Demo.xcworkspace \
  -scheme Demo \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

命令从仓库根目录执行。Podfile 的 post_install 会将 iOS/watchOS 依赖及资源 bundle 的部署版本提升到各自 Demo 的最低版本（依赖原有更高版本时保留），不修改 AudioPlayer podspec 的对外兼容范围，无需命令行覆盖部署版本。测试会操作全局音频会话和 Now Playing，因此不要并行运行测试类。

Demo 保留了仓库原有的 Pods。Podfile 的兼容补丁修正旧版 Kingfisher 对非可选 placeholder 返回值再次做可选绑定的问题；重新安装依赖后也会应用，更新到没有旧代码的版本时自动跳过。

## Xcode 27 普通运行

打开 `Demo/Demo.xcworkspace`，选择 `Demo` scheme 和 iPhone 设备，执行 Product → Run。根目录的 AudioPlayer 工程构建的是库，`DevicePlayback` scheme 用于 UI 测试。

DemoTests 的 Debug/Release 使用与 Demo 一致的自动签名和 Team。更换开发账号时需同步修改 App 与测试 target 的签名设置。

iPhone Demo 已移除对旧 Watch App 的构建依赖及嵌入阶段，保留 Watch target 和源码。Xcode 27 不再支持原有 WatchKit Extension 产品类型；Watch 示例需迁移到单 target watchOS App 后才能在该版本 Xcode 中运行。因此普通 iPhone Run 不会安装配套 Watch App，Watch 联动不属于本次运行验证范围。

## 覆盖范围

| 测试类 | 用例数 | 验证内容 |
| --- | ---: | --- |
| PlaybackTests | 31 | 自动播放、暂停恢复、倍速、准备阶段 seek、连续及向后 seek、资源重载、AAC 解码、结束重播、循环、失败恢复、非法参数、MP3、40 轮操作与释放、两分钟播放、audioMix 复制与音轨绑定、切资源隔离、nil 兼容、停止及失败清理 |
| SeekLifecycleTests | 16 | 旧 completion 迟到、取消只完成一次、失败进度、回调内 seek/切资源/stop、旧通知隔离、多代理重入事件顺序、实例释放 |
| HTTPPlaybackTests | 15 | 本机 HTTP 文件、Range 响应、重定向、404、网络准备中 pause/stop、AAC/M4A 网络解码、慢响应、断流/恢复、401、坏文件、HLS VOD |
| SessionAndRemoteTests | 10 | 中断恢复许可、中断期间暂停或切资源、设备断开、音频服务重置、前后台恢复与主动暂停、锁屏速率 |
| DemoIntegrationTests | 16 | Manager 恢复与切换；真实 PCM 1×/2×、限幅、连续切换及暂停保留、加载取消、tap 状态释放和资源缺失 |

合计 88 项。真实播放使用运行时生成的低振幅 WAV 和 AAC/M4A；网络测试的 HTTP 服务仅绑定 `127.0.0.1` 的临时端口，无需外网。乱序 completion 测试注入可控 AVPlayer，只接管 seek 完成时序，资源准备仍由 AVFoundation 执行。

## 维护约定

- 保留 `State.playing` 表示资源已就绪的兼容语义，实际播放状态读取 `control`。
- 播放器应由主线程创建、访问和销毁；KVO 和 seek 的系统回调会回到主线程消费。
- 被覆盖、停止或切资源取消的 seek，业务 completion 收到一次 `false`；迟到回调不能覆盖新资源。
- 寻时期间保留原有目标进度展示；完成后依据实际到达位置校准，失败不能继续显示未到达的目标。
- 当前验证在 iPhone 18 Pro / iOS 27.0 模拟器完成：51 通过、0 失败、0 跳过；独立 framework 也已构建通过。
- 系统中断和路由测试使用通知验证策略，不能代替真机来电、蓝牙、AirPlay、后台挂起与长时间弱网验证。
- 当前 Xcode 对 Demo 原有同步音频会话配置给出主线程性能提示；这不属于测试失败，后续可独立改造会话配置流程。

## 三轮复审记录

1. 状态与行为兼容性：检查 prepare/play/pause/stop、结束重播、中断和后台策略。修正前台通知到达时仍读取旧 applicationState 而阻止恢复的问题，加入显式生命周期标记；新增两项前后台回归测试。
2. 异步与代理重入：检查 KVO、迟到 completion、取消、销毁和多代理广播。测试复现旧 seekBegan 在新请求之后仍派发、暂停后仍广播旧 playing、finished 后仍广播旧 ready；按资源、生命周期、寻时代次和当前控制状态逐代理校验。新增四项多代理回归测试，覆盖 began/ended、控制状态与资源状态。
3. 测试与工程配置：核对共享 scheme、测试文件编译归属、Podfile、已跟踪 Pods 和独立 framework 工程。将 DemoTests 的 Foundation 引用改为 SDKROOT，移除固定 SDK 版本路径，并校正锁屏同步注释。

复审覆盖当前未暂存和新增文件；暂存区为空。CocoaPods 生成配置按构建关联检查，不手工改写第三方实现；Kingfisher 的既有编译兼容补丁保留。新增回归先验证失败，再修复并全量运行。最终 51 项通过；独立 framework 编译、工程 plist 检查、Podfile 语法检查和 git diff --check 均通过。

## 真机扩展验证

本轮增加 13 项后，Demo scheme 共 64 项，在 iPhone 16e / iOS 27.0.1 全部通过。另用系统实际切换 App 的脚本验证允许/禁止后台播放两条链路，均通过。详见 [真机验证记录](DEVICE-VALIDATION.md)。

`DevicePlayback` 为独立 UI scheme，包含四项页面/系统交互用例；本轮真机 runner 启用自动化模式超时，尚不能算执行通过。它不影响 Demo scheme 的库与集成测试。两分钟连续播放不能代替数小时稳定性或内存泄漏分析，来电、蓝牙、AirPlay、锁屏、蜂窝/Wi-Fi 切换仍未覆盖。

## audioMix 扩展回归

新增 6 项测试验证 AVAudioPlayerResource 的配置快照、原 asset 身份和音轨参数、实际播放推进、新 mix 替换、nil/URL/AVURLAsset 不继承旧 mix、停止与失败解除当前 item 及资源引用。测试检查 AVPlayerItem 上的音量参数，不等于测量扬声器输出，也不包含 MTAudioProcessingTap 算法、实时线程安全或 HLS tap 支持验证。

## 手工试听音量增强

运行 Demo，在列表右上角点击 **AudioMix**，进入“AudioMix 案例”。使用内置《夜曲》，无需网络。进入前暂停列表播放，返回停止试听，不自动恢复列表播放；独立试听不修改队列和记录，也不接管锁屏命令。

1. 点击“播放 / 继续”，先用原始音量播放几秒。
2. 在“原始音量 1× / 音量增强 2×”之间切换：当前时间应持续推进，不从头播放。
3. 点击暂停，再切换增强：仍停在原位置；点击继续后按当前选择播放。
4. 可拖动进度后再次切换；停止或退出应清理资源及处理器。加载中切换以最新选择为准，加载中暂停/停止取消准备。

2× 使用 MTAudioProcessingTap 放大 PCM 振幅；超出 [-1, 1] 的值限幅，可能产生削波失真，不代表听感响度翻倍。原音模式仍保留同一个 tap，目标增益为 1；切换只发布原子目标，在一个音频块内平滑过渡，不替换 item 或 mix。目标在下一次 tap 处理时生效，已处理并排队的音频不会被改写，实际听感切换可能有系统缓冲延迟。

实现：`Demo/Controller/AudioMixExampleController.swift`（页面与取消）、`Demo/AudioProcessing/AudioMixVolumeBoost.swift`（mix/tap 生命周期）、同目录 `.c`（实时 PCM 处理）。C 回调支持原生字节序紧密排列 Float32/Int16/Int32；其他格式保持原样并显示未支持。当前真机验证使用实际协商的 PCM 格式，不代表所有输入格式、HLS、受保护内容或 AirPlay 已验证。

库的 `AVAudioMixControlling.update(audioMix:for:)` 另有三项测试，检查同一 item/进度/控制状态、复制和 nil 移除、拒绝错误 asset 及停止后的更新。替换任意 mix 可能引发系统处理链重配置；增强开关复用 tap 可避免这类反复配置。

## 原播放页增强与 mix 案例扩展

原播放页的“音量增强 2×”开关直接作用于 Manager 当前 asset；Manager 与普通播放并行加载音轨并安装 tap，之后切换只修改原子增益。加载中读取最新偏好，停止、失败、切歌或销毁取消旧任务，增强失败不重建资源、不阻断原音。开关表示用户目标，状态文字区分准备中、等待 PCM、格式不支持与实际处理运行。

AudioMix 页面默认使用本地《夜曲》WAV，提供增强、无 mix、固定 25%、5 秒淡入和 2 秒淡出 / 2 秒恢复。包络从选择时的媒体时间开始，暂停时不推进；切换不 prepare、不 seek。增强开关与其他包络案例分开，避免误以为两个处理会叠加。

新增 8 项集成回归：主播放增强切换与切歌偏好、HTTP WAV/AAC/MP3 的真实 1→2→1 PCM 峰值、延迟网络加载取消、mix 参数与时间包络、准备中案例选择、原播放页 UISwitch 事件及可见布局。HTTP 服务仍仅监听本机，不能代表公网 HTTPS、鉴权、HLS 或 AirPlay 增强兼容。

最新验证：iPhone 16e / iOS 27.0.1 默认配置 **88 项通过、0 失败**，含上述新增 8 项；模拟器为 87 项全量通过，加原播放页开关 1 项单独通过。详见 [最新真机记录](DEVICE-VALIDATION.md#原播放页增强与-audiomix-多案例最新)。
