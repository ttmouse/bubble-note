#!/bin/bash
# 停止 BubbleNote
pkill -x BubbleNote && echo "BubbleNote 已停止" || echo "BubbleNote 未在运行"
