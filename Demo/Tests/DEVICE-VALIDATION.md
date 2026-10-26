# 真机验证记录（2026-10-26）

测试设备：有线连接的 iPhone 16e / iOS 27.0.1，已启用开发者模式。验证使用 Debug 签名构建和真实 AVFoundation 后端；本轮未修改播放器核心逻辑。真机自动化测试资源为离线生成的低振幅正弦波，包含 WAV、AAC/M4A、MP3 和 HLS VOD。

## 已执行的测试

| 范围 | 证据与边界 |
| --- | --- |
| 原有回归 | 51 项首次真机全量通过，覆盖播放、seek 时序、会话策略和 Demo Manager 集成 |
| 网络异常 | 慢响应下播放/暂停/切资源、响应前断连后显式重新准备、401、坏文件失败恢复；服务运行于测试机自身的 127.0.0.1，不代表蜂窝或 Wi-Fi 切换 |
| 真正缓冲耗尽 | 使用 180 秒 MP3、4 KB 分块和受控供数暂停；必须收到系统 AVPlayerItemPlaybackStalled 通知。验证恢复供数继续播放，以及用户暂停后底层 rate 维持零、媒体时间稳定 |
| 媒体格式 | 本地 MP3 向后 seek、HTTP HLS VOD 播放列表与分片加载、seek 后实际推进；不包含直播和动态 DVR 窗口 |
| 反复操作 | 40 轮准备/seek/取消/停止后仍能播放；另 40 轮创建/释放确认引擎解除持有、item 清空、周期观察者移除 |
| 连续播放 | 两分钟 MP3 连续播放，每十秒检查真实媒体时间推进；不等于数小时稳定性、耗电或内存分析 |

补充了 13 项 XCTest；Demo scheme 共 64 项。最终结果见下方执行证据。

## 真实前后台

使用 Debug 专用启动参数 `--playback-device-tests`，直接进入原有 AudioPlayerController 页面，播放原有 AudioPlayerManager 管理的两条离线测试项目。诊断器只提供控件标识、媒体状态和真实生命周期事件记录，不替换播放器实现。

通过 devicectl 把 Settings 切到前台，使 Demo 真实进入后台；停留七秒后再次激活同一个 Demo 进程。读取 App 沙盒诊断文件，要求后台与前台事件计数均增加，避免把默认零值误判为成功。这是实际系统 App 切换，不是发送模拟通知；也不代表实际 Home 按钮、锁屏或长时间挂起都已验证。

两条链路均通过：允许后台时实际媒体时间增加 **6.637 秒**；禁止后台时增加 **0.000 秒**，后台记录为 paused，回到前台后恢复 playing。

可重跑：

```sh
python3 Demo/Tests/verify-device-background.py --device DEVICE_UDID --output /tmp/audioplayer-background-results
```

需先构建并安装本次 Debug Demo。脚本会激活 Settings 和 Demo，结束后恢复普通 Demo 启动并停止测试音频。

[原始状态与截图目录](/private/tmp/audioplayer-fix/background-evidence)

## UI 自动化阻塞

已新增独立 `DevicePlayback` scheme 与四项 UI 用例：页面播放/暂停/拖动/上一集下一集、Home 后允许后台继续、禁止后台后恢复、控制中心暂停。用例已编译，但本次真机 UI runner 在执行测试前报错：

> The test runner failed to initialize for UI testing. Timed out while enabling automation mode.

因此这四项 UI 用例 **尚未执行成功，不能记为通过**。为避免影响正常回归，Demo scheme 只运行 64 项库与集成测试，UI 测试单独运行。排查测试机的“设置 → 开发者 → Enable UI Automation / UI 自动化”设置、屏幕解锁状态及 Xcode 设备连接后再执行 DevicePlayback；这里是排查入口，尚未证实具体根因。

## 仍待验证

- 真机来电、Siri 和其他 App 抢占音频；现有通知用例只验证代码策略。
- 蓝牙断连/重连、耳机按键、AirPlay、锁屏与控制中心实际远程命令；用户当前无法人工配合，UI runner 也未能初始化。
- 蜂窝/Wi-Fi 切换、TLS/鉴权刷新、长时间弱网、HLS 直播/DVR。
- 数小时连续播放、耗电、memgraph/Leaks 和多 iOS 版本/型号。
- Watch 通信及全部原始 Demo 页面交互。

## 重现方式

在仓库根目录执行，替换设备 UDID 和签名 Team：

```sh
xcodebuild test \
  -workspace Demo/Demo.xcworkspace \
  -scheme Demo \
  -destination 'platform=iOS,id=DEVICE_UDID' \
  -parallel-testing-enabled NO \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

运行 UI 用例时将 scheme 改为 `DevicePlayback`。两个 scheme 分别运行，避免与全局音频会话和 Now Playing 相互干扰。测试会安装 Demo 和相应 XCTest runner。

`generate-media.sh` 可用 ffmpeg 重新生成已提交的 MP3/HLS 夹具；日常运行测试无需 ffmpeg 或外网。

## 最终结果与证据

- iPhone 16e / iOS 27.0.1：**64 项通过、0 失败、0 跳过**，全量运行约 174 秒。
- 真实前后台两条脚本链路通过，单独统计，不并入 64 项 XCTest。
- DevicePlayback 独立真机 build-for-testing 成功；四项 UI 用例仍受环境阻塞。
- Podfile 语法、工程 plist 和 git diff --check 检查通过。

[全量 XCTest 结果](/private/tmp/audioplayer-fix/device-final.xcresult) · [全量运行日志](/private/tmp/audioplayer-fix/device-final.log) · [UI runner 阻塞结果](/private/tmp/audioplayer-fix/device-expanded-2.xcresult)

早期供数暂停测试曾错误地用 timeControlStatus == paused 推断卡顿，WAV 路径未满足该假设；已改为长 MP3 和系统真实卡顿通知，并在最终全量回归通过。此过程没有据此改动库的播放逻辑。

## Xcode 默认配置复验

直接使用 Xcode 27.0 的工程配置复现了多个 Pods 部署版本过旧、armv7k 废弃、旧 WatchKit Extension 产品类型不受支持的问题；去掉命令行 Team 覆盖后又发现 DemoTests 未配置 Team。

Podfile 现在会在安装时统一依赖及其资源 bundle 的部署版本；iPhone Demo 解除旧 Watch target 的构建依赖与嵌入，Watch 源码保留但需另行迁移单 target；DemoTests 的 Debug/Release 补齐与 App 一致的自动签名和 Team。

不覆盖 IPHONEOS_DEPLOYMENT_TARGET、WATCHOS_DEPLOYMENT_TARGET 或 DEVELOPMENT_TEAM，也不传 allowProvisioningUpdates，已完成以下复验：

- Debug 真机构建、签名、安装及无测试参数启动成功。
- 同一默认配置运行全部 64 项 XCTest：0 失败，测试耗时约 166 秒。
- 测试结束后恢复普通 Demo 启动成功。
- Podfile 语法、工程 plist、锁文件一致性和 git diff --check 通过。

[默认配置构建日志](/private/tmp/audioplayer-fix/normal-run-fixed.log) · [默认配置测试结果](/private/tmp/audioplayer-fix/normal-config-tests-fixed.xcresult) · [默认配置测试日志](/private/tmp/audioplayer-fix/normal-config-tests-fixed.log)

## audioMix 资源扩展验证

新增 AVAudioPlayerResource 将 AVURLAsset 和可选 AVAudioMix 绑定；初始化时复制 mix，后端复用同一个 asset，并在交给 AVPlayer 前赋给新 item。原有 URL/AVURLAsset 行为保持兼容。

新增 6 项回归后，在同一 iPhone 16e / iOS 27.0.1 使用默认工程配置执行 **70 项全部通过，0 失败**。独立 framework 编译通过（沿用当前 SDK 支持的 iOS 15 编译覆盖参数），Demo 真机测试未覆盖部署版本或签名。测试验证 mix 参数与播放生命周期，不代表 tap 音效、扬声器输出幅度或 HLS 处理已验证。

[70 项真机测试结果](/private/tmp/audioplayer-fix/audio-mix-tests.xcresult) · [真机测试日志](/private/tmp/audioplayer-fix/audio-mix-tests.log) · [独立 framework 构建日志](/private/tmp/audioplayer-fix/audio-mix-framework.log)

## Demo AudioMix 试听案例

列表新增 AudioMix 页面，提供原始 URL、nil mix、25% 音量、5 秒淡入、淡出/静音/恢复五种案例。使用内置音频，独立播放器，进入暂停主播放、退出停止试听；异步音轨加载具有取消和代次校验。

新增 5 项 Demo 集成测试，验证 mix 时间包络参数、五种页面模式实际播放、暂停恢复、退出清理、快速切换/停止/销毁及缺失资源提示。真机全量 **75 项通过、0 失败**。模拟器实际点击列表入口、25% 模式和暂停，截图检查布局正常；这不代表扬声器音量已经测量。

[75 项真机测试结果](/private/tmp/audioplayer-fix/mix-demo-full.xcresult) · [运行日志](/private/tmp/audioplayer-fix/mix-demo-full.log)

## Castbox 式原音 / 2 倍增强切换

将试听页调整为同一首歌的增强开关。准备时安装一份包含 MTAudioProcessingTap 的 mix；原音/增强只原子更新处理器的 1/2 倍目标，块内平滑并限幅，不 prepare、seek、重建 item 或替换 mix。当前实现以 Demo 内置本地歌曲为试听资源。目标影响下一次处理，系统已排队的音频可能造成听感延迟。

库新增 AVAudioMixControlling.update(audioMix:for:)：同步校验当前 asset 实例并赋给现有 item，支持 nil 移除，不缓存到新资源。任意 mix 替换可能引发系统处理链重配置，因此增强开关复用 tap。

验证：

- 真机实际 tap 处理低振幅 PCM，峰值比依次为 1、2、1；稳定增强处理帧计数增加。
- 0.75 输入峰值经 2 倍增强后输出限幅为 1，无数值溢出。
- 连续切换 20 次保持资源、处理器、进度和播放控制；暂停时切换保持暂停，继续后原位置推进。
- 加载期间使用最新偏好，暂停/停止取消；反复创建并播放后停止，C 状态最终全部 finalize，页面不被异步任务持有。
- 通用 mix 更新保留同一个 item/进度/播放意图，支持 nil，拒绝旧 asset 和停止后的更新。
- 模拟器实际点击播放、增强、暂停、恢复原音：暂停保持在 48.8 秒，已处理帧数与目标状态可见，布局正常。
- 独立 framework 编译通过（当前 SDK 使用 iOS 15 编译覆盖）；Demo 默认配置真机 **80 项通过、0 失败**，测试约 174 秒。

完整回归曾发现原有后台暂停状态竞态：底层 timeControlStatus 迟到为 playing，覆盖了后台策略。新增可控播放器确定性复现失败后，统一播放许可判断，状态广播和实际起播都优先遵守后台策略，并在代理重入后重新读取最新许可。该回归已包含在 80 项中。

此验证不等于对扬声器响度、零缓冲延迟、HLS/AirPlay、所有 PCM 格式或数小时稳定性作保证。2 倍为 PCM 振幅增益，接近满幅内容会产生限幅失真。

[最终 80 项真机测试结果](/private/tmp/audioplayer-fix/live-boost-verified.xcresult) · [运行日志](/private/tmp/audioplayer-fix/live-boost-verified.log) · [独立 framework 构建日志](/private/tmp/audioplayer-fix/live-mix-framework-final.log)

## 原播放页增强与 AudioMix 多案例（最新）

在同一 iPhone 16e / iOS 27.0.1 使用 Demo 默认配置执行 **88 项测试全部通过，0 失败**。本次新增 8 项 Demo 集成回归，完整执行约 188 秒（测试阶段）。模拟器先执行 87 项全量通过，随后新增的原播放页开关测试单独通过。

- 原播放页新增“音量增强 2×”开关：同一 asset / tap 上修改增益，验证暂停、进度、倍速保留，以及切歌继承增强偏好。
- 本机 HTTP WAV、AAC/M4A、MP3 均通过真实 Manager 加载与解码，实际 tap 峰值依次为 1、2、1；增强时播放时钟继续推进，暂停切换保持位置。
- 延迟网络加载被切歌或清空取消，迟到结果不能覆盖当前资源或重新起播。
- AudioMix 独立页增加无 mix、固定 25%、5 秒淡入、2 秒淡出/2 秒恢复；验证当前 asset、进度、暂停及音量包络参数，加载中采用最新案例。
- 原播放页测试通过真实 UISwitch 的 valueChanged 事件驱动共享管理器，检查处理器目标、资源身份、暂停位置及控件可见布局。这是 App 内集成测试，不计作独立 DevicePlayback UI 自动化通过。

网络服务仅监听 127.0.0.1。上述结论不覆盖公网 HTTPS/TLS、所有编码组合、持续弱网供数时的增强、HLS tap、DRM、蓝牙或 AirPlay。包络验证检查系统参数和播放推进，没有测量扬声器声压。既有同步 AVAudioSession 调用仍有主线程性能提示，不影响本轮测试结果。

[88 项真机结果](/private/tmp/audioplayer-fix/main-boost-device.xcresult) · [真机日志](/private/tmp/audioplayer-fix/main-boost-device.log) · [87 项模拟器结果](/private/tmp/audioplayer-fix/main-boost-full.xcresult) · [原播放页开关模拟器结果](/private/tmp/audioplayer-fix/main-boost-ui-switch.xcresult)
