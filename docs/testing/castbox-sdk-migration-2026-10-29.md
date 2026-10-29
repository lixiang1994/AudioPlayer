# Castbox 主播放迁移：AudioPlayer 最小 SDK 修改

日期：2026-10-29（Asia/Shanghai）。基线 commit：`2e3ebcf`（1.7.0）。修改直接落在 `/Users/lee/Documents/Code/Github/AudioPlayer`，未提交、未发布、未改版本。

## 当前结论

源码与新增回归测试已落地。最新一次按原配置、原断言、原实际顺序在 iPhone16e / iOS27.0.1 完整执行 **135 项：135 通过、0 失败、0 跳过**，无自动失败重试。此前正式源码全量 **134/135** 的 HTTP AAC 失败仍保留，最新通过只说明该轮未复现，根因未解决；不得宣称已修复偶发问题。本次新增 **13 项全部通过**，包括真实 EOF 后暂停 seek、显式 0、原生监控和会话 opt-out。测试 target、独立 SDK Release 编译及 iOS/watchOS pod lint（明确的工具链 target 覆盖）通过。模拟器包括新建专用设备均因 DTServiceHub 服务权限错误未执行用例。真机测试进程已退出，独占使用已结束。

## 输入与边界

- 开始前读取仓库现有 SDK、测试及 Demo 测试说明，工作区干净；仓库、下级目录和各父目录未发现适用的 AGENTS.md。
- 指定 SDK 路径位于本聊天默认可写范围之外；已通过批准的实际文件创建/删除检查，随后直接编辑该仓库，未以副本代替落地。
- 以 Castbox 仓库 `docs/patches/playback-sdk/AudioPlayer-session-position.patch`、`AudioPlayer-finished-paused-seek.patch` 及 `docs/testing/audioplayer-migration-finished-seek-draft-2026-10-29.md` 为审查起点；只读取该仓库。
- 对比 `/private/tmp/castbox-before-local-sdk-20261029/Pods/AudioPlayer/Sources/AV/` 中的 `AVAudioPlayer.swift`、`AVAudioPlayerResource.swift`：两文件与本次修改前 SDK 版本完全一致，没有额外已验证能力需要迁回。
- 不改 Castbox、GuruPlayer、VideoPlayer 或已安装 Pods；没有运行 Castbox 主 App。所有构建产物及完整日志位于 `/private/tmp/audioplayer-castbox-sdk-20261029/`。

## 实现

1. `AudioPlayerConfiguration.handlesAudioSessionNotifications` 默认为 `true`；创建实例时置 `false` 后不注册 interruption、route change、media services reset 三类通知。宿主负责会话事件策略；前后台通知及 `allowedBackgroundPlayback` 保留原行为。SDK 仍不配置或激活 AVAudioSession。
2. 新增可选只读 `AVAudioNativePlaybackMonitoring.nativePlaybackSample` 和 `AVAudioNativePlaybackSample`，保留草案类型和属性名，不增加 `AudioPlayerable` 的必选要求，不暴露可变 AVPlayer/item。快照必须主线程读取：`position` 直接来自已就绪 item 的 `currentTime()`，不使用目标显示或 currentTimeCalibrator；未就绪、清理后、seek 排队或执行期间为 nil。`seekPending` 包含显式 0 请求；`rate` 直接读取底层 AVPlayer.rate；`sampledAt` 使用 systemUptime 单调秒数。原生 item 采样不证明物理声音输出。
3. ready item 在 `.finished` 收到 seek 时重新进入 `.playing`（已就绪生命周期），不修改暂停意图。继续复核资源代次及请求身份后走现有 startSeek，显式 0 不被丢弃；状态回调内 stop、切资源或新 seek 可正确取消旧请求。默认自然结束后的 play 从头重播和循环路径保留。
4. README 补充开关、采样语义和 EOF seek 行为；`State.playing` 文档明确 finished 后 seek 也会回到 ready。

## 回归测试

在现有测试文件添加 13 项，Demo scheme 由 122 增至 135 项（Playback 32、SeekLifecycle 25、SessionAndRemote 14、HTTP 15、DemoIntegration 49）。

- 真实媒体：24 秒运行时 WAV seek 到 23.7，再实际播放到 EOF，未注入结束通知；暂停 seek 到 2、再显式 seek 0，要求完成一次、ready/pausing、原生时间正确、底层 rate 0 且等待 0.3 秒稳定。另测 EOF 后直接 0，再 play 从头继续。
- 原生监控：公开 Builder 返回实例可转换能力协议；暂停和播放中的实际 position/rate、单调采样时间、准备阶段 0 pending、连续覆盖与迟到 completion、失败、stop、切资源不残留上次位置。
- finished 状态代理重入：stop、prepare 新资源、再次 seek 分别隔离旧请求。
- 会话开关：false 下三类通知不暂停、不恢复、不清理资源；前后台策略仍生效。既有默认 true 的中断、路由、重置测试保留，并断言新开关默认 true。

本次新增 13 项最终均已在本仓库实际真机运行通过。草案临时宿主的 121/121 真机记录只作为历史输入，不并入本仓库通过数量。

## 验证证据

| 检查 | 结果 | 完整证据（目录前缀均为 `/private/tmp/audioplayer-castbox-sdk-20261029/`） |
| --- | --- | --- |
| `git diff --check`、podspec Ruby 语法、两个工程 plutil | 通过 | 本报告末尾证据摘要 |
| Demo `build-for-testing`，模拟器默认签名 | `TEST BUILD SUCCEEDED`，包含 135 项测试源码 | `build-signed-tests.log`、`SignedDerivedData/` |
| 独立 AudioPlayer 工程 Release，generic iOS Simulator | `BUILD SUCCEEDED`；单次构建覆盖 iOS target 15.0 | `framework-release.log` |
| 原样 `pod lib lint AudioPlayer.podspec --platforms=ios,watchos --no-clean --verbose` | 失败：Xcode 27.1 拒绝 podspec 的 iOS 12 deployment target（当前支持 15.0…27.1）；watchOS 编译通过 | `pod-lib-lint.log` |
| 同一 podspec、本地源码、全部 iOS/watchOS subspec lint；临时 xcconfig 覆盖 iOS target 15.0 | `AudioPlayer passed validation.`，无 allow-warnings | `pod-lib-lint-xcode27.log`、`xcode27-lint.xcconfig` |
| 未修复产品的真实 EOF 两项负对照 | 未进入测试；共享 iOS 27 模拟器出现并发任务，停止本任务后切独立模拟器仍有 runner 连接故障 | `eof-negative.xcresult`、`eof-negative-isolated.xcresult`、`eof-negative-isolated.log` |
| 修复后 SeekLifecycle + SessionAndRemote | iOS 27 / iOS 18.6 都未进入用例，DTServiceHub 无法连接；默认签名也未解决 | `focused-signed.xcresult`、`focused-signed.log`、`focused-ios18.xcresult`、`focused-ios18.log` |
| 重启专用 iPhone16e/iOS18.6 模拟器后全 scheme 重试 | 仍未进入用例，停止空等进程，不能计为 135 项通过 | `full-ios18-reboot.xcresult`、`full-ios18-reboot.log` |

lint 的临时配置仅为 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`，运行命令：

```sh
XCODE_XCCONFIG_FILE=/private/tmp/audioplayer-castbox-sdk-20261029/xcode27-lint.xcconfig \
pod lib lint AudioPlayer.podspec --platforms=ios,watchos --no-clean --verbose
```

未修改 podspec 的 iOS 12 / watchOS 9 最低版本声明；通过当前工具链 lint 不能声称已验证 iOS 12。

运行器共同错误为 `DTServiceHubClient failed to bless service hub`，下层为 `Failed to get valid task for analysis pid`。专用模拟器重启、iOS 18.6/27 切换、模拟器签名启用均未解决；`DevToolsSecurity -status` 已显示 enabled。未重置整机服务或终止其他 SDK 任务。启动失败、中止和 0 executed 都不算产品测试失败复现或通过。

## 待验证

- 本次新增 13 项和原有 SDK 生命周期/通知用例已完成真机验证；最终全量中既有 Demo 集成失败仍需单独排查，未扩大本次最小 SDK 修改范围。
- 模拟器服务权限恢复后补跑 135 项及未修复负对照；不能把草案宿主通过数量迁移为本仓库通过数量。
- iOS 12、旧系统矩阵、Watch 实机运行、真实来电/蓝牙/AirPlay、实际 media-services reset、物理音频输出尚未在本轮验证。通知注入仅验证 SDK 策略；watchOS lint 仅验证编译。
- Castbox 主 App 的本地 SDK 集成构建和迁移验收由主聊天负责，本任务不修改该仓库。


## 真机最终结果与复跑过程

主聊天随后明确分配设备 `00008140-000D1962348A801C`，授权本任务独占运行。使用仓库实际 Demo workspace 和 CocoaPods 本地 SDK，未复制 SDK 实现。

1. `device-full.xcresult`：135 项完整执行，134 通过、1 失败。新增重置 opt-out 测试在 control 刚变 playing 后固定 0.1 秒采样，媒体时钟仍为 0。仅修改该新测试，先有界等待实际位置 >0.1，再发通知并有界等待继续推进；SDK 业务源码不改。`device-session-fixed.xcresult` 随后 14/14 通过。
2. `device-full-final.xcresult`：复跑中既有 Demo HTTP AAC 静音加速及稳定加速计数断言失败。我在该全量进程退出前启动了两项复跑，导致同一测试 App 受到干扰并出现额外取消/失败。此轮不作为有效完整回归。两项单独复跑 `device-flaky-retry.xcresult` 为 2/2 通过，但不能据此宣称全量已绿。错误操作已记录，并在后续等待进程退出、确认设备无测试进程后才开始最终严格串行全量。
3. **最终有效轮 `device-full-serial.xcresult`：135 项，134 通过、1 失败、0 跳过。** 完整日志 `device-full-serial.log`。本次新增 13 项全部通过；EOF 2/0 秒原生位置、pending=false、rate=0 和暂停稳定性由测试直接断言。未以 current 的乐观目标代替实际位置。默认中断、路由、重置策略及原有资源/取消/循环重播均实际执行。

最终失败原文：

```text
/Users/lee/Documents/Code/Github/AudioPlayer/Demo/Tests/DemoIntegrationTests.swift:907: error: -[DemoTests.DemoIntegrationTests testHTTPAACSilenceAcceleration] : XCTAssertEqualWithAccuracy failed: ("1.3184387360841687") is not equal to ("3.0") +/- ("0.35")
Test Case '-[DemoTests.DemoIntegrationTests testHTTPAACSilenceAcceleration]' failed (4.694 seconds).
```

最终失败的 Demo 静音处理实现和该测试文件本轮未修改；此前第一轮完整运行该用例通过，单独复跑也通过，最终串行全量再次失败。它说明目前全量验收存在时序/性能波动，不能直接断定与 SDK 修改无关；本次默认 true 路径与普通播放速率逻辑未变，仍应在后续独立排查中对基线及设备负载做对照。

完整复现命令（最终轮使用已构建的 DeviceDerivedData）：

```sh
xcodebuild test-without-building \
  -workspace Demo/Demo.xcworkspace -scheme Demo \
  -destination 'platform=iOS,id=00008140-000D1962348A801C' \
  -derivedDataPath /private/tmp/audioplayer-castbox-sdk-20261029/DeviceDerivedData \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /private/tmp/audioplayer-castbox-sdk-20261029/device-full-serial.xcresult
```

xcresulttool 新版 summary 在当前 Xcode 返回 `unknown/0 tests`，与终端逐项 XCTest 执行记录不一致；计数依据日志中的 started/passed/failed、各 suite 的 Executed 与最终 TEST EXECUTE 状态，保留 xcresult 不虚报解析成功。

用户进一步要求新开专用模拟器：已创建 `AudioPlayer SDK 20261029`（iOS18.6，`51120925-BC9E-4204-A5BA-3244A1080D55`），全量启动仍出现相同 DTServiceHub 错误，0 项进入。证据 `full-fresh-ios18.xcresult`、`full-fresh-ios18.log`；已停止空等并关闭该专用模拟器，未删除设备，也未占用其他会话模拟器。

## 源码证据指纹

| 文件 | SHA-256 |
| --- | --- |
| `Sources/Core/AudioPlayerConfiguration.swift` | `f0fbd5c154b2f3bb1fbed153122b8831155ab1c7b7856a0415e66e516343fb06` |
| `Sources/Core/AudioPlayer.swift` | `fb6b838d1c86735be3359745ce2e3f7cc8c785d5d3ef8ce7e827b0b18282edca` |
| `Sources/AV/AVAudioPlayer.swift` | `6e6c49be02e0142c860be1eeb877c7a65f1b23e0c678779e7c7ecd973f946af6` |
| `Sources/AV/AVAudioPlayerResource.swift` | `fb41b37c9fbc9c5b504bc383c6ece4ed926c1cd24d01537ef81284f472bfe816` |
| `Demo/Tests/SeekLifecycleTests.swift` | `191b476656d5a5617f1619a8462c64d183b9bb06324e629ab94a5b1d47f079d3` |
| `Demo/Tests/SessionAndRemoteTests.swift` | `2fdd3f87a22d738a30e207cf2bb1ed33ea820d082a8313d969aa83284ba0c4ee` |

可随仓库保留的日志摘要及日志 SHA-256 见 [验证证据摘要](castbox-sdk-migration-2026-10-29-evidence.txt)。完整 xcresult 与 lint 工作区保留在上述临时目录，不将构建产物提交到仓库。


## HTTP AAC 唯一失败继续定位（16:33 收口设备，根因仍待定位）

用户要求继续定位后，读取原始完整日志、旧版 xcresult 用例对象和实际测量附件。原始附件已导出 `original-failed-aac-measurement.txt`：`HTTP m4a: target=3.0, media/uptime=1.3184387360841687`。原失败中 HTTP 请求、boost PCM、playing/loading、结束时加速状态断言均通过，仅 0.3 秒媒体时钟倍率断言失败。不能仅凭这些结束状态排除测量窗口内发生瞬时退速或重配置。

Video 明确释放设备后，本任务严格串行运行以下对照，没有和其他设备任务交叠：

| 证据（同一临时目录前缀） | 结果 |
| --- | --- |
| `device-http-aac-rerun.xcresult` | 正式源码原始测试单项 1/1 通过 |
| `device-aac-diagnostic5.xcresult` | 10ms 循环采样诊断，单项连续 5/5 通过 |
| `device-integration-diagnostic.xcresult` | 带诊断的完整 Demo 集成组 49/49 通过 |
| `device-baseline-integration.xcresult` | 修改前 HEAD 原始 SDK、原始断言完整 Demo 集成组 49/49 通过 |
| `device-integration-timer2.xcresult` | 保留原始 `pump(0.3)`，用 10ms Timer 在内存记录原生位置/rate/缓冲/静音代次，两轮完整集成组 98/98 通过 |
| `device-baseline-full.xcresult` | 修改前 HEAD 源码完整 122/122 通过，0 失败、0 跳过，约 283.9 秒，16:33:29 进程退出 |

诊断窗口读取实际 AVPlayerItem 时间和 AVPlayer.rate（内部测试用反射读取，不增加 SDK 可变接口）；均看到目标和底层 rate 3，媒体时钟约 3×、缓冲已到结尾、loading ended。两轮 Timer 诊断共 128 条采样全部 `rate=3.0`、`accel=true`，未捕获退速或断流。网络服务器原 sentBytes 字段仅统计分块发送路径，当前完整发送路径显示 0 不能解释为未下载；本次不以该字段 0 证明 HTTP 失败。

基线工程位于临时 `baseline/`，核心/AV 源码及 seek/session/集成测试逐文件与 HEAD 字节比较一致，指纹保存在 `aac-baseline-manifest.json`，构建日志确认编译来源为 baseline/Sources。它只用于对照，不代替正式仓库落地，也不改安装 Pods。

**结论限制：** 单项及诊断组成功不能覆盖原全量失败；修改前完整基线通过也不能单独证明本轮回归。当前未复现原错误，不足以归因于 HTTP/AAC 系统限制、既有问题或本轮 SDK 修改。因此没有调整 SDK 业务、放宽 ±0.35 实测阈值、增加“重试至通过”或声称修复完成。正式 `DemoIntegrationTests.swift` 已恢复与 HEAD 一致；临时观测修改不进入交付。更低扰动的 rate KVO 诊断已编译、尚未运行，补丁保存在 `aac-kvo-diagnostic.patch`，后续可在协调独占时段观察窗口内 rate 事件和 accelerationCount 变化，或增加可重复的预热/测试顺序对照。

主聊天要求让出设备后未再启动新轮次；当前基线轮退出并核对无真机 xcodebuild 进程，**iPhone16e 00008140-000D1962348A801C 已在 16:33:29 后释放给 Guru**。仍保留前文最终正式源码全量 134/135 结果，唯一失败未被本轮“单项通过”抹除。


## 原配置完整 135 项单轮重跑（18:47 结束）

主聊天明确释放物理 iPhone16e 后，仅执行一次原始完整 135 项，未使用 `-retry-tests-on-failure`、`-test-iterations` 或失败自动重试；原 scheme Debug、并行测试 NO、原 DerivedData 路径及原断言保留。仅在运行前用原仓库 build-for-testing 更新产物，避免之前诊断版本混入。未使用 allowProvisioningUpdates，不修改任何已安装 Pods、签名源配置或版本，不发版。

**结果：135/135 通过、0 失败、0 跳过；135 个唯一测试各执行一次。** `test.log` 的实际 started 顺序与原 `device-full-serial.log` 中 135 项顺序逐项完全一致。原 scheme/xctestrun 未设置随机顺序、显式 seed；本轮不新增 seed，manifest 记录 `explicit_random_seed=null`，不伪造不存在的种子。运行前后源码/夹具/测试/配置 SHA-256 一致。

证据目录：`/private/tmp/audioplayer-castbox-sdk-20261029/original135-rerun/`。完整结果 `result.xcresult`、命令日志 `test.log`、构建日志 `build.log`、源代码差异 `source.diff`、原执行顺序 `original-order.json`、xctestrun 和运行前源码快照 `before.json` 均保留。

实际保存的效果附件已从 xcresult 导出：

| 测试 | 实际附件 / 断言结果 |
| --- | --- |
| HTTP AAC/M4A 静音加速 | target 3.0，媒体时钟/uptime **2.999970258480181×**；原测试同时断言 HTTP 请求 >0、boostedFrames >4096、控制 playing、loading ended、仍处静音加速并在有声区退出 |
| HTTP MP3 静音加速 | target 3.0，媒体时钟/uptime **3.000001449812072×** |
| 本地 WAV 原生速率/媒体时钟 | target 3.0、AVPlayer.rate 3.0，媒体时钟/uptime **2.9999655359381525×** |
| 原音/2× PCM tap | `testBoostTapActuallyProcessesOriginalAndDoubleGain` 通过；保留原输入/输出增益和处理帧断言，无新增物理声音测量 |

仓库内最终 [manifest](castbox-sdk-migration-2026-10-29-original135-manifest.json) 包含完整命令、实际 135 项顺序、结果计数、源码配置指纹、附件文本与哈希、日志哈希和原始失败引用；临时目录保留同一 manifest。所有“倍率”是媒体时钟/AVPlayer 与 PCM 回调证据，不能证明扬声器物理输出。

**风险结论：** 此轮全过，原 AAC 1.3184387360841687× 失败未复现。未改业务逻辑或弱化测试，因而没有证据声称原竞态根因已定位/解决；历史失败仍是潜在间歇性风险，原始 xcresult 和失败附件完整保留。后续若重现，应基于失败窗口内 rate/timeControl/静音连续性/调度证据继续定位，不能用这次通过覆盖历史失败。

测试进程于 18:47:14 结束、exit 0；随后核对无设备 xcodebuild 进程，**物理 iPhone16e 已释放**，未启动新真机轮次。
