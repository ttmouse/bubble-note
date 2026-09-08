# BubbleNote - Mac 右下角气泡备忘

在 Mac 桌面右下角显示一个置顶的深色圆角气泡，把指定文案持续展示在屏幕上。
文案可通过终端命令随时替换，适合人工或各种 AI agent 调用。

## 快速使用

安装后任意终端执行：

```bash
note 文字内容            # 设置气泡文案
note "多行\n文字"       # 引号保留换行
echo 文字 | note        # 管道输入
note                    # 查看当前文案
note --clear            # 清空（气泡隐藏）
note --help             # 帮助
```

`note` 命令位于 `~/.local/bin/note`（软链到本目录 `note`），已在 PATH 中。

## 效果

- 气泡固定在屏幕右下角（Dock 上方），置顶显示
- 半透明深色圆角背景 + 白色文字，鼠标点击穿透不挡操作
- 文案改变后约 2 秒内自动刷新，无需重启

## 手动操作

```bash
cd ~/Downloads/GPT插件/bubble-note
./build.sh       # 编译 BubbleNote.app（修改源码后执行）
./start.sh       # 启动/激活气泡
./stop.sh        # 停止气泡（关闭显示）
echo 新文案 > message.txt   # 直接改文件也能触发更新
```

## 原理

| 组件 | 说明 |
|------|------|
| `BubbleNote.swift` | Swift/AppKit 原生无边框置顶窗口，绘制气泡 |
| `message.txt` | 文案源文件，唯一内容入口 |
| `note` | CLI 包装：写 message.txt + 必要时自动拉起 BubbleNote |
| 更新机制 | 目录监听（即时）+ 每 2 秒轮询兜底；已禁用 App Nap |

- BubbleNote 以 `.app` 形式通过 `open` 启动，确保进入用户图形会话（从 SSH/agent 环境调用也能正常显示）。
- 所有窗口相关逻辑在进程内完成，不依赖登录项；开机自启可后续把 app 加入「系统设置 → 登录项」。

## 项目文件

```
bubble-note/
├── BubbleNote.swift      # 源码
├── BubbleNote.app/       # 编译产物（Contents/Info.plist 等）
├── message.txt           # 文案文件
├── note                  # CLI 主脚本
├── build.sh / start.sh / stop.sh
└── README.md
```

## 常见问题

- 气泡没显示：确认进程在运行 `pgrep -x BubbleNote`；不在则 `note 文字` 会自动拉起或 `./start.sh`。
- 改了文案没反应：等待约 2 秒轮询；检查 message.txt 是否真的被修改。
- 想改样式（颜色/字号/圆角/位置）：编辑 `BubbleNote.swift` 顶部 `Config` 后 `./build.sh` 并重启。
