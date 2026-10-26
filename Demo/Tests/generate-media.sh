#!/bin/sh
# 用纯正弦波生成真机夹具，无外网或版权音频；测试直接使用已提交文件，无需运行此脚本。
# 重新生成需要本机 ffmpeg，固定编码参数以覆盖 MP3 和 HLS/AAC 的不同加载路径。
set -eu
fixture_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/Fixtures"
mkdir -p "$fixture_dir"
ffmpeg -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=180' -af volume=0.02 -ar 44100 -ac 2 -codec:a libmp3lame -b:a 32k -y "$fixture_dir/tone.mp3"
ffmpeg -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=16' -af volume=0.02 -ar 44100 -ac 2 -c:a aac -b:a 32k -f hls -hls_time 4 -hls_playlist_type vod -hls_segment_filename "$fixture_dir/segment%02d.ts" -y "$fixture_dir/tone.m3u8"
