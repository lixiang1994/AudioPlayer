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
