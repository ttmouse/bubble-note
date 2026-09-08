#!/bin/bash
# 构建 BubbleNote.app
cd "$(dirname "$0")"
APP_DIR="BubbleNote.app/Contents/MacOS"
mkdir -p "$APP_DIR"
echo "编译 BubbleNote ..."
swiftc -O BubbleNote.swift -o "$APP_DIR/BubbleNote"
if [ $? -eq 0 ]; then
    chmod +x "$APP_DIR/BubbleNote"
    echo "构建成功: $(pwd)/BubbleNote.app"
else
    echo "构建失败"
    exit 1
fi
