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

## 原播放页增强与 AudioMix 多案例（2026-10-26）

在同一 iPhone 16e / iOS 27.0.1 使用 Demo 默认配置执行 **88 项测试全部通过，0 失败**。本次新增 8 项 Demo 集成回归，完整执行约 188 秒（测试阶段）。模拟器先执行 87 项全量通过，随后新增的原播放页开关测试单独通过。

- 原播放页新增“音量增强 2×”开关：同一 asset / tap 上修改增益，验证暂停、进度、倍速保留，以及切歌继承增强偏好。
- 本机 HTTP WAV、AAC/M4A、MP3 均通过真实 Manager 加载与解码，实际 tap 峰值依次为 1、2、1；增强时播放时钟继续推进，暂停切换保持位置。
- 延迟网络加载被切歌或清空取消，迟到结果不能覆盖当前资源或重新起播。
- AudioMix 独立页增加无 mix、固定 25%、5 秒淡入、2 秒淡出/2 秒恢复；验证当前 asset、进度、暂停及音量包络参数，加载中采用最新案例。
- 原播放页测试通过真实 UISwitch 的 valueChanged 事件驱动共享管理器，检查处理器目标、资源身份、暂停位置及控件可见布局。这是 App 内集成测试，不计作独立 DevicePlayback UI 自动化通过。

网络服务仅监听 127.0.0.1。上述结论不覆盖公网 HTTPS/TLS、所有编码组合、持续弱网供数时的增强、HLS tap、DRM、蓝牙或 AirPlay。包络验证检查系统参数和播放推进，没有测量扬声器声压。既有同步 AVAudioSession 调用仍有主线程性能提示，不影响本轮测试结果。

[88 项真机结果](/private/tmp/audioplayer-fix/main-boost-device.xcresult) · [真机日志](/private/tmp/audioplayer-fix/main-boost-device.log) · [87 项模拟器结果](/private/tmp/audioplayer-fix/main-boost-full.xcresult) · [原播放页开关模拟器结果](/private/tmp/audioplayer-fix/main-boost-ui-switch.xcresult)


## 静音加速与独立开关（2026-10-27，初次验证）

本轮修改仅在 Demo：复用同一 tap，先检测原始 PCM，再执行独立的 1× / 2× 振幅增益；主线程根据最新媒体时间窗口在连续安静 300ms 后临时调速，最高 2×。保存用户倍速，暂停、seek、关闭、停止和观测过期时恢复。未修改播放器库公共 API。

iPhone 18 Pro / iOS 27 模拟器全量 **98 项通过、0 失败、0 跳过**，测试阶段约 192 秒。新增 10 项验证：时间线确认与过期、滞回与有声退出、四种开关组合的真实 PCM、用户倍速/暂停/seek/案例切换、右声道声音保护、HTTP WAV 实际加速、样本生成取消、实际控件事件以及页面/定时器/tap 释放。既有两分钟连续播放测试也通过。

首次定向测试发现 tap 的实际前瞻通常只有几十毫秒，350ms 前瞻要求会让加速始终不触发，已根据真实 PCM 与媒体时间证据改成实时检测。检测与调速有延迟，不能保证语音起点完全不被加速；合成信号验证不代表自然播客听感已通过。未验证长时间自然语音、持续弱网下的该功能、全部 PCM 格式、HLS tap、DRM、蓝牙或 AirPlay。继承的同步 AVAudioSession 主线程性能提示仍存在。

已尝试在 iPhone 16e 运行本轮全量测试：签名构建完成，设备因锁屏无法启动 DemoTests，取消等待。因此**本轮没有真机通过结果**。设备日志保留锁屏错误，取消等待后的退出信息不作为产品运行失败。

[98 项模拟器测试结果](/private/tmp/audioplayer-fix/silence-simulator-full.xcresult) · [本轮真机启动日志](/private/tmp/audioplayer-fix/silence-device-full.log)


## 静音加速三轮复审（2026-10-27，模拟器阶段）

本轮复审覆盖未暂存改动及新增文件，暂存区为空；保留已有工程修改，播放器库核心仍未修改。发现并修复 4 项：

- 关闭静音加速后仍进行 PCM 分析：独立运行开关控制 C 检测，关闭时清时间线并保留音量增强。
- 媒体时钟冻结时旧观测不失效：采用可注入的单调时钟，250ms 未收到新观测则判过期。
- 连续静音中速率反复切换：实测同段进入加速 6 次。系统调速会短暂重建 tap，并改变解码前瞻；已增加最多 250ms 自身重配置保护，并用连续静音范围判断当前位置。修复后的完整静音段只进入一次加速，自然结束重播也重新启用检测。
- 批量读取中短有声窗口被末尾静音覆盖：累计有声代次跨时间线重置保留，延续加速须匹配代次；出现新声音后重新确认连续静音，过渡保护不能绕过该条件。

新增 4 项回归均先复现失败、再验证修复。Demo 集成测试 **30 项全部通过**，最终 iPhone 18 Pro / iOS 27 模拟器全量 **102 项通过、0 失败、0 跳过**，测试约 206 秒。既有同步 AVAudioSession 主线程性能提示仍存在。本轮不增加真机通过声明；此前设备锁屏未执行的限制仍然有效，自然语音、弱网及远程输出路由仍需另外评测。

[最终 102 项全量结果](/private/tmp/audioplayer-fix/silence-review-full.xcresult) · [30 项 Demo 集成结果](/private/tmp/audioplayer-fix/silence-review-integration.xcresult)

## 再次三轮复审与真机验证（2026-10-27）

本次 iPhone 16e 已解锁，成功执行测试，不再沿用上轮锁屏阻塞结论。首先完成既有 102 项真机回归；补齐缺口、修复断流许可后 109 项通过；实际后台又发现冷启动会话问题，修复并补测试后，最新真机全量 **110 项通过、0 失败、0 跳过**。其中 Demo 集成 38 项，主播放和 AudioMix 的允许 / 禁止后台四条脚本链路另行统计。

三轮复审检查检测与并发、播放生命周期组合、测试及工程证据。本轮修复两项确证问题：

- **断流许可**：时间缺口或 streamID 改变后，没有新声音也不能跨连续段沿用原静音许可。增加连续证据代次，重新确认 300ms；自身调速 250ms 有界保护保留。新增回归先失败后通过，正常倍速和 0.5× 下连续静音均稳定。
- **冷启动后台**：直接进入独立页时未配置音频会话，真实后台停在约 5.87 秒。原主播放页会配置会话，导致先播放过列表时掩盖该问题。独立页播放时现在自行配置并激活 playback；只停止自己的播放，不在退出时停用全局会话。补充从 ambient 类别开始的冷启动回归，并重新执行真实后台和完整测试。

| 本次场景 | 真机证据与边界 |
| --- | --- |
| 基本播放 / seek / 结束重播 / 取消 / 释放 | 110 项中包含既有核心回归及真实页面集成；未替换 AVFoundation 解码 |
| 双开关与用户倍速 | 四组合、原始信号检测、0.5× / 1× / 1.5× / 2×、非法值、临时速率恢复、30 轮快速操作、同一资源与暂停意图 |
| 网络静音 PCM | HTTP WAV、MP3、AAC/M4A 实际检测并加速，有声时恢复；MP3/AAC 同时开启增强并检查实际处理帧数 |
| 静音与真实卡顿 | 长 MP3 停止供数并收到系统 PlaybackStalled 后撤销加速；恢复供数继续播放；再次卡顿中暂停后恢复供数仍保持底层 rate=0 |
| 会话组合 | 静音活跃时中断开始 / 有许可恢复 / 中断中用户暂停、输出失效、服务重置；通知注入只验证策略，不能算真实来电或蓝牙操作 |
| 稳定性 | 连续静音不反复调速、结束重播、30 轮双开关 / 倍速 / seek，另有既有 40 轮操作 / 释放与两分钟连续播放；不是数小时压力或耗电评估 |
| AudioMix 真实后台 | Settings / Demo 实际切换，生命周期计数增加。允许后台媒体差约 8.783 秒，加速次数 1→2，增强帧数 124707→461038；禁止后台进度差 0 秒、基础速率 1×，回前台恢复 |
| 主播放页真实后台 | 同样系统切换：允许后台差约 6.668 秒；禁止后台差 0 秒；两条均回前台恢复 |
| 系统 UI | 重试 DevicePlayback，runner 在执行用例前启用自动化模式超时，四项用例仍未通过 |

后台测试数据与截图保留在独立证据目录；它们不等同于真实 Home、锁屏或控制中心远程命令验证。系统重置测试保留处理器引用以确认停止检测，避免把页面主动清空引用误判失败。校正后的短有声批量回归包含在最终 110 项中。

修改仅在 Demo 与验证资料，保留既有工程修改，未改播放器库 Sources。工程 plist、脚本语法及 git diff --check 通过。仍有同步 AVAudioSession 主线程性能提示。

[110 项真机结果](/private/tmp/audioplayer-fix/silence-review-device-110.xcresult) · [全量日志](/private/tmp/audioplayer-fix/silence-review-device-110.log) · [38 项集成结果](/private/tmp/audioplayer-fix/silence-review-session-final.xcresult) · [静音后台证据](/private/tmp/audioplayer-fix/silence-review-background-fixed/summary.json) · [主播放后台证据](/private/tmp/audioplayer-fix/silence-review-main-background/summary.json) · [UI runner 阻塞结果](/private/tmp/audioplayer-fix/silence-review-device-ui.xcresult)

未覆盖：真实来电 / Siri、物理蓝牙 / 耳机 / AirPlay、实际锁屏及控制中心命令、公网网络切换 / TLS / 长时间弱网、静音功能的 HLS / DRM、多音轨与全部 PCM 格式、自然语音轻声 / 噪声听感、多设备 / iOS 版本、数小时稳定性 / 能耗 / Leaks。不能把合成信号与通知测试等同于上述场景已通过。


## 静音 3× 与缓冲回退（2026-10-27）

当前静音目标为 3×，不支持超过 2× 时回退 2×，网络连续缓冲不足恢复用户倍速；音量增强仍独立。新增库的可选只读能力快照，算法与缓冲策略仍在 Demo。

- iPhone 16e / iOS 27.0.1 真机全量 **113 项通过、0 失败、0 跳过**，约 252 秒；其中 Demo 集成 41 项。
- 新增能力回退、缓冲滞回 / 尾段 / 非法值和快照生命周期 3 项；原有 HTTP WAV/MP3/AAC、真实卡顿恢复、双开关、暂停 / seek / 重播 / 释放及 0.5× / 2× 组合回归通过。
- 允许后台：实际 3×，后台期间新静音加速次数 1→2，增强帧数 128486→457259，回前台继续播放。禁止后台：暂停，rate=1，后台进度差 0 秒，回前台继续。
- 首轮资源准备连续超时，发现安装更新前的旧 Demo 与测试宿主并存；清理旧进程后 3 项单独复测及完整回归通过。首轮失败记录保留，不据此推断产品场景全部无问题。

[113 项结果](/private/tmp/audioplayer-silence3-full.xcresult) · [日志](/private/tmp/audioplayer-silence3-full.log) · [后台证据](/private/tmp/audioplayer-silence3-background/summary.json) · [首轮失败](/private/tmp/audioplayer-silence3-01.xcresult)

合成信号与通知测试不能替代自然播客试听、真实电话 / 路由、锁屏及多系统版本验证；3× 也不保证语音起点完全不受调速延迟影响。原有主线程音频会话性能提示仍存在。


## AudioMix 页面交互优化（2026-10-27）

- 页面按资源、播放进度、效果对比分区；原音频可直接控制增强与静音，不再要求选择单独的静音案例。
- 实时处理、无 mix、25%、淡入与淡出五项对比；包络模式保留双开关偏好但暂停应用，操作功能开关返回实时处理，保留资源与暂停位置。
- 声音 / 静音样本自动开启静音且保留增强；支持回到最初资源、取消未完成样本生成、暂停时跳至样本静音段。再次应用效果只重设包络起点。
- 开关旁显示用户／实际倍率、能力目标、等待／暂停／缓冲状态、加速次数、PCM 峰值比；包络模式显示插值后的音量目标，合成样本标出有声／静音段。这些数值不代表扬声器实测响度。

新增 3 项交互测试，覆盖默认开关与全部包络返回、控件事件、暂停及 item 身份、资源往返与取消、快捷 seek、包络再次应用与状态展示；既有静音关闭测试更新为切到无 mix 的新交互语义。最终 iPhone 16e / iOS 27.0.1 **44 项 Demo 集成测试全部通过，0 失败**，约 90 秒。首轮 44 项也通过；最终轮包含后续增加的包络目标显示断言。

本轮未重跑其余库测试；当前 scheme 共 116 项，之前库与 Demo 的完整回归为 113 项。真机截图核对最终布局，页面已运行，诊断记录确认实际 PCM 处理。自然语音、外部路由与旧系统版本的验证边界保持此前说明；仍有既有同步音频会话的主线程性能提示。

[最终 44 项结果](/private/tmp/audioplayer-mix-ui-final.xcresult) · [测试日志](/private/tmp/audioplayer-mix-ui-final.log) · [真机截图](/private/tmp/audioplayer-mix-ui-device-final.png)


## Review 修复后的最终验证（2026-10-27）

修复目标倍率误标与输入/输出峰值跨块配对，补连续缓冲区间边界测试。当前共 122 项：Demo 集成 49、Playback 32、Seek 16、HTTP 15、Session 10。

- iPhone 16e / iOS 27.0.1，用户确认独占测试机后，最终一轮 **122 通过、0 失败、0 跳过**，约 287 秒。
- 本地 WAV 的 AVPlayer.rate 为 3；本地 WAV、HTTP MP3、HTTP AAC 的媒体进度 / 单调时钟均约为 2.99997×，附件保存在结果包中。
- 两分钟连续播放推进至 120.25 秒，所有十秒采样持续播放；该轮附件未记录到中断或退后台。没有自动恢复或放宽连续推进断言。
- 前两轮分别 114/122、115/122 通过。第一轮有一条未同步的旧“实际倍率”文案断言，已改为目标倍率与播放状态；其余失败集中在意外暂停后的播放及会话用例。截图显示当时 Castbox 在前台，第一轮另有旧 Demo 进程；这提示可能存在并发干扰，不能据此证明唯一原因。两轮失败结果均保留，未计为通过。
- 修复后重新 review，未发现新的可确认代码问题。自然播客、真实来电、外部路由、旧系统与长时能耗仍未在本轮补测；既有同步会话激活的主线程风险提示仍存在。

[最终 122 项结果](/private/tmp/audioplayer-review-fixes-exclusive.xcresult) · [最终日志](/private/tmp/audioplayer-review-fixes-exclusive.log) · [测量与中断附件](/private/tmp/audioplayer-review-fixes-exclusive-attachments/manifest.json) · [修复后 Review](/private/tmp/audioplayer-review-fixes-review.md)

[首轮 114/122](/private/tmp/audioplayer-review-fixes-full.xcresult) · [第二轮 115/122](/private/tmp/audioplayer-review-fixes-final.xcresult)
