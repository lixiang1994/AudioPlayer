#!/usr/bin/env python3
"""通过公开 devicectl 接口切换真实 App，验证后台播放策略并保存状态和截图。"""
import argparse
import json
import subprocess
import time
from pathlib import Path


def run(device, *arguments):
    """只操作显式指定的测试机；命令失败立即暴露，避免把未切后台当成通过。"""
    result = subprocess.run(
        ["xcrun", "devicectl", "device", *arguments[:2], "--device", device, *arguments[2:]],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def snapshot(device, output, name):
    """读取 Demo 自己写出的诊断文件，不访问测试机的其他 App 数据。"""
    destination = output / (name + ".json")
    run(device, "copy", "from", "--source", "Documents/playback-device-state.json",
        "--domain-type", "appDataContainer", "--domain-identifier", "com.audio.player.demo",
        "--destination", str(destination))
    return json.loads(destination.read_text())


def main():
    """运行允许/禁止后台两条链路；无论成功或失败，最后结束测试音频并恢复普通 Demo。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="已连接测试机的 UDID")
    parser.add_argument("--output", required=True, type=Path, help="本次独立证据目录")
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = []
    try:
        for allowed in [True, False]:
            name = "allowed" if allowed else "blocked"
            run(arguments.device, "process", "launch", "--terminate-existing",
                "--environment-variables", json.dumps({"PLAYBACK_ALLOW_BACKGROUND": "1" if allowed else "0"}),
                "com.audio.player.demo", "--playback-device-tests")
            time.sleep(3)
            before = snapshot(arguments.device, output, name + "-before")
            assert before["control"] == "playing" and before["current"] > 0.5, before
            # 激活 Settings 产生真实的系统生命周期事件，不发送模拟通知。
            run(arguments.device, "process", "launch", "com.apple.Preferences")
            time.sleep(7)
            during = snapshot(arguments.device, output, name + "-during")
            assert during["backgroundCount"] > 0 and during["applicationState"] == 2, during
            if allowed:
                assert during["control"] == "playing", during
            else:
                assert during["control"] == "paused", during
            run(arguments.device, "process", "launch", "com.audio.player.demo")
            time.sleep(2)
            after = snapshot(arguments.device, output, name + "-after")
            # 必须是同一实例收到前后台事件，重新创建诊断器后的默认零值不算成功。
            assert after["foregroundCount"] > 0 and after["control"] == "playing", after
            delta = after["backgroundDelta"]
            assert delta > 5 if allowed else abs(delta) < 0.6, after
            run(arguments.device, "capture", "screenshot", "--destination", str(output / (name + ".png")))
            results.append({"case": name, "before": before, "during": during, "after": after, "passed": True})
            print(json.dumps(results[-1], ensure_ascii=False), flush=True)
        (output / "summary.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    finally:
        run(arguments.device, "process", "launch", "--terminate-existing", "com.audio.player.demo")


if __name__ == "__main__":
    main()
