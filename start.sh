#!/bin/bash
# 启动 BubbleNote（通过 open 交给图形会话，已在运行则激活）
cd "$(dirname "$0")"
open "./BubbleNote.app"
sleep 1
if pgrep -x BubbleNote > /dev/null 2>&1; then
    echo "BubbleNote 已在图形会话中运行"
else
    echo "启动失败，请先执行 ./build.sh"
    exit 1
fi
