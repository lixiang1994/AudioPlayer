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
| PlaybackTests | 32 | 自动播放、暂停恢复、倍速、准备阶段 seek、连续及向后 seek、资源重载、AAC 解码、结束重播、循环、失败恢复、非法参数、MP3、40 轮操作与释放、两分钟播放、audioMix 复制与音轨绑定、切资源隔离、nil 兼容、停止及失败清理、连续缓冲区间乱序 / 重叠 / 空洞 / 非法时间 |
| SeekLifecycleTests | 16 | 旧 completion 迟到、取消只完成一次、失败进度、回调内 seek/切资源/stop、旧通知隔离、多代理重入事件顺序、实例释放 |
| HTTPPlaybackTests | 15 | 本机 HTTP 文件、Range 响应、重定向、404、网络准备中 pause/stop、AAC/M4A 网络解码、慢响应、断流/恢复、401、坏文件、HLS VOD |
| SessionAndRemoteTests | 10 | 中断恢复许可、中断期间暂停或切资源、设备断开、音频服务重置、前后台恢复与主动暂停、锁屏速率 |
| DemoIntegrationTests | 49 | Manager 恢复与切换；真实 PCM 1×/2×、限幅、连续切换及暂停保留、加载取消、tap 状态释放和资源缺失；目标倍率与暂停文案、底层倍率及单调时钟实测、变幅 PCM 峰值配对、诊断页导航返回、静音时间线、滞回与过期、双开关真实 PCM、倍速恢复、右声道保护、HTTP、样本取消、控件事件和定时器释放 |

合计 122 项。真实播放使用运行时生成的低振幅 WAV 和 AAC/M4A；网络测试的 HTTP 服务仅绑定 `127.0.0.1` 的临时端口，无需外网。乱序 completion 测试注入可控 AVPlayer，只接管 seek 完成时序，资源准备仍由 AVFoundation 执行。

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


## 静音加速案例（2026-10-27）

AudioMix 默认“实时处理”可直接开启静音；点击“声音 / 静音样本”切资源并自动开启静音。样本是本地 14 秒 WAV：2～6、8～12 秒静音，其余有声。音量增强和静音加速独立开关；用户倍速单独保存，静音优先 3×，不支持超过 2× 时回退 2×；网络连续缓冲不足恢复用户倍速。加载样本会更换资源，开关不会。

新增 10 项集成测试，覆盖原始信号检测、实际增益与速率、HTTP WAV、暂停/seek/切案例恢复、样本取消、控件事件和释放。非零低振幅片段用于证明检测在增强之前进行，右声道独立信号用于防止声道平均漏判。网络验证使用本机 HTTP 文件，不代表公网弱网、HTTPS、HLS tap 或远程路由已验证。

tap 无固定前瞻，本例以连续 300ms 安静和最新媒体时间窗口决策，声音恢复或窗口过期后撤销加速。调速可能短暂影响语音起点，仍需自然播客试听和设备评测；合成信号测试不能证明语音质量。

本轮 iPhone 18 Pro / iOS 27 模拟器全量 **98 项通过、0 失败、0 跳过**，测试阶段约 192 秒。iPhone 16e 连接正常但锁屏，Xcode 无法启动测试，已取消等待；上一轮 88 项真机通过不代表本次新增功能已真机验证。仍有既有同步 AVAudioSession 主线程性能提示。

[98 项模拟器测试结果](/private/tmp/audioplayer-fix/silence-simulator-full.xcresult)


## 静音案例三轮复审（2026-10-27）

复审覆盖本次 C 音频回调、Swift 时间线与倍速仲裁、Demo 页面、测试及文档；未暂存修改和新增文件均已检查，暂存区为空。原有工程配置修改保留。

1. 音频与检测：关闭开关后原先仍在分析 PCM，媒体进度冻结时旧证据也不会随真实时间过期。已分别由运行开关控制 C 检测、在主线程采用单调时钟 250ms 超时，两个复现测试先失败再通过。
2. 调速时序与生命周期：持续播放发现单段静音反复进入加速 6 次。自己调速会短暂重建 tap，且增加解码前瞻；已加入最多 250ms 重配置保护，使用连续静音范围维持加速，移除把较多前瞻误判为过期的限制。持续静音现在只触发一次；自然结束重播重新绑定，保留双开关和用户倍速。
3. 批量结果与覆盖：短有声窗口可能被同一批末尾静音掩盖。已增加有声窗口代次，任何新声音都会撤销旧的延续许可，不允许通过重配置保护掩盖声音。复现测试先失败，修复后通过；补齐文档中的媒体时间和重配置边界。

本次新增 4 项复审回归，Demo 集成测试共 30 项已全部通过；全 scheme 共 102 项。

最终 iPhone 18 Pro / iOS 27 模拟器全量 **102 项通过、0 失败、0 跳过**，测试约 206 秒。真机仍未执行本轮新增验证。

[三轮复审后全量测试结果](/private/tmp/audioplayer-fix/silence-review-full.xcresult)

## 再次三轮复审与真机回归（2026-10-27）

1. **检测证据与断流**：重新检查 C 队列、取消代次、时间窗口和速率许可。新测试复现：没有新声音但发生流切换或丢窗时，旧许可仍可绕过 300ms 确认。已增加连续证据代次；有声代次与连续代次都匹配才能延续。自身调速仍只允许有界过渡保护，连续静音稳定性回归通过。
2. **播放与会话组合**：新增 HTTP MP3/AAC 静音样本，实际验证 PCM、临时速率和有声退出；停止供数后必须收到 AVPlayerItemPlaybackStalled，验证恢复与卡顿中主动暂停；补齐静音活跃时中断、用户暂停、路由失效、服务重置、30 轮双开关 / 倍速 / seek 操作、0.5× 稳定性和用户 2× 时按媒体能力加速。真实后台额外复现独立页冷启动未配置会话，已在播放时自行配置并激活 playback，不依赖主列表提前播放。
3. **生命周期与验证证据**：复核取消、重播、定时器与 tap 释放、编译归属、注释和测试判据。短有声批量回归同时传入有效连续代次，避免默认参数让测试失去针对性。Debug 后台入口复用实际页面，检查后台进入新静音段和增强帧数增加。主播放与 AudioMix 的允许 / 禁止后台四条链路通过。

本次新增 8 项，最新真机全量 **110 项通过、0 失败、0 跳过**；其中 Demo 集成 38 项。修改仅涉及 Demo 与验证资料，未修改 Sources 播放器库。原有工程改动保留，暂存区为空。早先 109 项通过后，真实后台验证仍发现了冷启动会话问题，说明前台全量通过不能代替实际系统行为验证；修复后重新执行本次完整 110 项。

压缩静音夹具随 Demo 打包；`generate-media.sh` 可重新生成 180 秒 MP3 与 14 秒 AAC/M4A，日常测试不需要 ffmpeg。静音缓冲测试使用长 MP3 和本机分块服务，不代表公网、TLS 或网络切换。

```sh
python3 Demo/Tests/verify-device-background.py --device DEVICE_UDID --silence --output /tmp/audioplayer-silence-background
```

不传 `--silence` 时验证主播放页。四条真实后台链路不并入 110 项 XCTest 数量。UI runner 仍在启用自动化模式时超时，四项系统 UI 用例不计作通过。自然语音、真实来电、外部路由、多系统版本与数小时稳定性仍未验证；同步音频会话配置仍有主线程性能提示。

[110 项真机全量结果](/private/tmp/audioplayer-fix/silence-review-device-110.xcresult) · [全量日志](/private/tmp/audioplayer-fix/silence-review-device-110.log) · [38 项集成结果](/private/tmp/audioplayer-fix/silence-review-session-final.xcresult) · [最新真机记录](DEVICE-VALIDATION.md#再次三轮复审与真机验证2026-10-27)


## 静音目标 3× 与缓冲回退（2026-10-27）

静音目标改为固定 3×，实际 item 不支持超过 2× 时回退 2×，用户基础倍速保持 0.5～2×。新可选能力 `AVAudioPlaybackMonitoring.playbackCapacity` 提供主线程快照；未就绪返回 nil。缓冲只计算当前位置可连续抵达的区间，进入需要目标倍率下 2 秒余量，低于 0.5 秒余量退出；本地文件及已缓冲到结尾的尾段例外。检测、开关、seek 与速率切换保护沿用现有流程。

新增 3 项测试覆盖媒体能力回退、未知能力、缓冲门槛与滞回、完整尾段、非法缓冲值及 item 生命周期；原有真实播放用例同步验证新倍率，包含用户 2× 与 0.5× 的连续静音稳定性。iPhone 16e / iOS 27.0.1 全量 **113 项通过、0 失败、0 跳过**，其中 Demo 集成 41 项。首轮出现连续资源准备超时；清理残留的旧 Demo 进程后，3 项针对性复测和完整回归均通过，首轮结果不计为通过。

真实后台允许 / 禁止两条链路重新通过：允许后台时进入新的静音段、增强帧数继续增长，禁止后台时暂停且恢复基础 1×，回前台恢复。诊断文件记录到实际 3×，有声时恢复 1×。这些真实后台检查不并入 113 项计数；自然语音听感与外部设备限制仍见此前验证边界。

[113 项真机结果](/private/tmp/audioplayer-silence3-full.xcresult) · [全量日志](/private/tmp/audioplayer-silence3-full.log) · [后台证据](/private/tmp/audioplayer-silence3-background/summary.json)


## AudioMix 页面交互优化（2026-10-27）

- 页面按资源、播放进度、效果对比分区；原音频可直接控制增强与静音，不再要求选择单独的静音案例。
- 实时处理、无 mix、25%、淡入与淡出五项对比；包络模式保留双开关偏好但暂停应用，操作功能开关返回实时处理，保留资源与暂停位置。
- 声音 / 静音样本自动开启静音且保留增强；支持回到最初资源、取消未完成样本生成、暂停时跳至样本静音段。再次应用效果只重设包络起点。
- 开关旁显示用户／实际倍率、能力目标、等待／暂停／缓冲状态、加速次数、PCM 峰值比；包络模式显示插值后的音量目标，合成样本标出有声／静音段。这些数值不代表扬声器实测响度。

新增 3 项交互测试，覆盖默认开关与全部包络返回、控件事件、暂停及 item 身份、资源往返与取消、快捷 seek、包络再次应用与状态展示；既有静音关闭测试更新为切到无 mix 的新交互语义。最终 iPhone 16e / iOS 27.0.1 **44 项 Demo 集成测试全部通过，0 失败**，约 90 秒。首轮 44 项也通过；最终轮包含后续增加的包络目标显示断言。

本轮未重跑其余库测试；当前 scheme 共 116 项，之前库与 Demo 的完整回归为 113 项。真机截图核对最终布局，页面已运行，诊断记录确认实际 PCM 处理。自然语音、外部路由与旧系统版本的验证边界保持此前说明；仍有既有同步音频会话的主线程性能提示。

[最终 44 项结果](/private/tmp/audioplayer-mix-ui-final.xcresult) · [测试日志](/private/tmp/audioplayer-mix-ui-final.log) · [真机截图](/private/tmp/audioplayer-mix-ui-device-final.png)


## Review 问题修复与独立观测（2026-10-27）

AudioMix 的倍率展示改为用户倍率、当前目标与播放状态，避免把保存的目标当作实际执行值。实时处理与包络模式都验证暂停时的文案和媒体位置；底层 AVPlayer 暂停时 rate 为 0，即使目标仍为 1.5×。

本地 WAV、HTTP MP3/AAC 的静音加速新增媒体进度 / 单调时钟测量；本地同时检查底层 AVPlayer 的 rate 与 timeControlStatus。测量在连续静音中部进行，不跨 seek、暂停或有声边界，允许系统调度误差。实测倍率以 XCTest 附件保存，供独立核对。

PCM 输入/输出峰值改为一个 64 位无锁原子快照；强弱相邻块高频读取测试要求两种振幅都实际出现，且同块峰值比保持 2×。帧计数、格式标志与峰值并非同一时刻的整份快照。

另补连续缓冲区间乱序、重叠、毫秒衔接、当前位置前片段、真实空洞、空区间和无效时间测试；两项导航回归覆盖诊断模式的正常/空窗口入口与返回清理。两分钟连续播放保留原有断言，新增被动记录系统中断、前后台通知及控制变化的附件，不自动恢复或掩盖意外暂停。


## Review 修复后的最终验证（2026-10-27）

修复目标倍率误标与输入/输出峰值跨块配对，补连续缓冲区间边界测试。当前共 122 项：Demo 集成 49、Playback 32、Seek 16、HTTP 15、Session 10。

- iPhone 16e / iOS 27.0.1，用户确认独占测试机后，最终一轮 **122 通过、0 失败、0 跳过**，约 287 秒。
- 本地 WAV 的 AVPlayer.rate 为 3；本地 WAV、HTTP MP3、HTTP AAC 的媒体进度 / 单调时钟均约为 2.99997×，附件保存在结果包中。
- 两分钟连续播放推进至 120.25 秒，所有十秒采样持续播放；该轮附件未记录到中断或退后台。没有自动恢复或放宽连续推进断言。
- 前两轮分别 114/122、115/122 通过。第一轮有一条未同步的旧“实际倍率”文案断言，已改为目标倍率与播放状态；其余失败集中在意外暂停后的播放及会话用例。截图显示当时 Castbox 在前台，第一轮另有旧 Demo 进程；这提示可能存在并发干扰，不能据此证明唯一原因。两轮失败结果均保留，未计为通过。
- 修复后重新 review，未发现新的可确认代码问题。自然播客、真实来电、外部路由、旧系统与长时能耗仍未在本轮补测；既有同步会话激活的主线程风险提示仍存在。

[最终 122 项结果](/private/tmp/audioplayer-review-fixes-exclusive.xcresult) · [最终日志](/private/tmp/audioplayer-review-fixes-exclusive.log) · [测量与中断附件](/private/tmp/audioplayer-review-fixes-exclusive-attachments/manifest.json) · [修复后 Review](/private/tmp/audioplayer-review-fixes-review.md)

[首轮 114/122](/private/tmp/audioplayer-review-fixes-full.xcresult) · [第二轮 115/122](/private/tmp/audioplayer-review-fixes-final.xcresult)
