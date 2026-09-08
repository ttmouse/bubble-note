# BubbleNote - 会变表情的 Mac 右下角气泡机器人

在 Mac 桌面右下角显示一个置顶的深色圆角气泡机器人：上方是表情脸，下方是文案。
平时它会根据文案情绪配表情、像活物一样温和地变化；也可以由你或 agent 用 `note` 命令指定情绪和内容。

## 快速使用

安装后任意终端执行：

```bash
note 文字内容              # 设置内容（表情维持现状）
note --happy 文字内容      # 指定开心脸 + 内容
note --auto 文字内容       # 不锁表情：机器人自主随机换脸
note                       # 查看当前内容与表情
note --list                # 列出全部可用情绪
note --clear               # 清空内容和表情（气泡隐藏）
note --help                # 完整帮助
```

### 情绪参数一览

| 参数 | 表情 | 参数 | 表情 |
|------|------|------|------|
| `--happy` / `--开心` | (•‿•) | `--sad` / `--难过` | (T_T) |
| `--joy` / `--满足` | (◕‿◕) | `--sleepy` / `--困` | zZ(-_-) |
| `--wink` / `--眨眼` | (｡•̀ᴗ-)✧ | `--meh` / `--无奈` | (︶︹︺) |
| `--cool` / `--元气` | (•̀ᴗ•́)و | `--angry` / `--生气` | (╬ Ò﹏Ó) |
| `--think` / `--思考` | (￣～￣) | `--shock` / `--呆` | (￣□￣) |
| `--huh` / `--疑惑` | (•_•)? | `--playful` / `--调皮` | (¬‿¬) |
| `--wow` / `--惊讶` | (⊙_⊙) | `--smug` / `--得意` | (￣▽￣) |
| `--neutral` / `--淡定` | (•_•) | `--face '(^_^)'` | 自定义任意颜文字 |

表情支持中文别名（如 `note --开心 快吃午饭了`）。agent 可用英文参数。

## 效果

- 深色圆角气泡固定屏幕右下角，置顶显示
- **情绪感知**：能看懂文案情绪时自动配表情（问句→疑惑、含"搞定/太棒了"→开心、含"延期/抱歉"→难过、含"困/睡觉"→犯困、含"方案/想想"→思考等）
- **正常表情**：判断不出情绪时，机器人只在平静表情池里温和变化（微笑/眨眼/元气等），不会乱摆负面脸
- `note --sad 文字` 等显式指定仍优先（锁定时不自主变化）
- 内容或表情变化后约 2 秒内自动刷新；点击气泡它像受惊小动物先蹦一下再溜走，内容更新后重新出现
- 字号放大（正文 30pt、表情 40pt），适合远看

## 手动操作

```bash
cd ~/Downloads/GPT插件/bubble-note
./build.sh       # 编译 BubbleNote.app（修改源码后执行）
./start.sh       # 启动/激活气泡
./stop.sh        # 停止气泡（关闭显示）
```

## 原理

| 组件 | 说明 |
|------|------|
| `BubbleNote.swift` | Swift/AppKit 原生无边框置顶窗口；表情行 + 正文富文本渲染 |
| `message.txt` | 文案源文件 |
| `emotion.txt` | 表情源文件（一行颜文字）；**不存在/为空 = 自主随机模式** |
| `note` | CLI 包装：解析情绪参数，写两个文件，必要时自动拉起 BubbleNote |
| 更新机制 | 目录监听（即时）+ 2 秒轮询兜底 + 禁用 App Nap |

- BubbleNote 以 `.app` 通过 `open` 启动进入用户图形会话（SSH/agent 环境也能正常显示）。
- 平静表情池与换脸间隔在 `BubbleNote.swift` 的 `Config.calmFaces` / `Config.aliveIntervalRange` 可调。
- 样式（颜色/字号/圆角/位置/背景）都在 `Config` 中可改。

## 项目文件

```
bubble-note/
├── BubbleNote.swift      # 源码
├── BubbleNote.app/       # 编译产物（已 git 忽略，可 ./build.sh 重建）
├── message.txt           # 文案文件
├── emotion.txt           # 表情文件（运行时生成，可忽略）
├── note                  # CLI 主脚本（软链到 ~/.local/bin/note）
├── build.sh / start.sh / stop.sh
├── .gitignore / README.md
```

## 常见问题

- 气泡没显示：`pgrep -x BubbleNote` 确认；不在则 `note 文字` 会自动拉起或 `./start.sh`。
- 想让它一直保持自主随机：确保没有 `emotion.txt`（`note --auto` 会清掉）。
- 改了内容没反应：等约 2 秒轮询；确认写的是 `message.txt` / `emotion.txt`。
- 想调换脸频率或表情集：改 `Config.calmFaces` 与 `Config.aliveIntervalRange` 后 `./build.sh`。
