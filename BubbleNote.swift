//
//  BubbleNote.swift
//  右下角气泡备忘展示工具
//
//  功能：
//    - 在 Mac 屏幕右下角弹出一个置顶的深色圆角气泡
//    - 文案读取自同目录的 message.txt（UTF-8），支持多行
//    - 实时监听 message.txt 变化，修改文件后气泡自动更新，无需重启
//    - 鼠标点击穿透，不干扰桌面操作
//
//  用法：
//    构建：  ./build.sh
//    启动：  ./start.sh          （或直接 ./BubbleNote）
//    停止：  ./stop.sh
//    可选：  ./BubbleNote --file /某个路径/message.txt
//

import Cocoa

// MARK: - 配置

struct Config {
    /// 距屏幕右边缘的间距
    static let rightMargin: CGFloat = 24
    /// 距屏幕底部(可见区域)的间距
    static let bottomMargin: CGFloat = 24
    /// 气泡最大宽度（原 400 的 2/3）
    static let maxWidth: CGFloat = 267
    /// 气泡内边距
    static let paddingH: CGFloat = 20
    static let paddingV: CGFloat = 14
    /// 圆角半径
    static let cornerRadius: CGFloat = 16
    /// 背景色 (白 alpha)
    static let background = NSColor(calibratedWhite: 0.12, alpha: 0.88)
    /// 文字颜色
    static let textColor = NSColor.white
    /// 字号（原 15 放大一倍）
    static let fontSize: CGFloat = 30
    /// 文本阴影
    static let hasTextShadow = true
}

// MARK: - 气泡视图（自绘圆角背景 + 文本标签）

final class BubbleView: NSView {

    let label = NSTextField(labelWithString: "")
    var text: String = "" {
        didSet { refresh() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        label.font = NSFont.systemFont(ofSize: Config.fontSize, weight: .medium)
        label.textColor = Config.textColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.isEditable = false
        label.isSelectable = false
        if Config.hasTextShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            label.shadow = shadow
        }
        // 不使用 Auto Layout：label 严格铺在 padding 内部，
        // 避免长文本的完整单行宽度通过约束把窗口撑大。
        autoresizesSubviews = false
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds,
                                xRadius: Config.cornerRadius,
                                yRadius: Config.cornerRadius)
        Config.background.setFill()
        path.fill()
    }

    // 手动排版：label 填满气泡内边距区域，文本按窗口宽度自动换行
    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: Config.paddingH, dy: Config.paddingV)
    }

    private func refresh() {
        label.stringValue = text
        needsDisplay = true
    }

    // MARK: 文本测量（宽度永远不超过 maxWidth，超长则增高换行）

    static func measure(text: String) -> NSSize {
        guard !text.isEmpty else { return .zero }
        let font = NSFont.systemFont(ofSize: Config.fontSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let rect = attrStr.boundingRect(
            with: NSSize(width: Config.maxWidth - Config.paddingH * 2,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        // 尾部 +8pt 缓冲：boundingRect 对中文全角字符的 advance 可能略低估，
        // 紧贴会裁掉右侧文字（如 30pt 字号下"加油"两个字约 60pt，文本区仅 58pt）。
        // 折行文本不受影响（其宽度已达约束上限）。
        let width = min(Config.maxWidth, ceil(rect.width) + Config.paddingH * 2 + 8)
        // 高度多留 4pt 缓冲，避免文字过长时被裁切
        let height = max(ceil(rect.height) + Config.paddingV * 2 + 4, 40)
        return NSSize(width: width, height: height)
    }
}

// MARK: - 应用委托

final class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var bubbleView: BubbleView!
    var messageURL: URL
    var dirSource: DispatchSourceFileSystemObject?
    var pollTimer: Timer?
    private var lastContent: String = ""
    private var activityToken: NSObjectProtocol?

    // MARK: 参数解析

    static func resolveMessageURL() -> URL {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--file"), idx + 1 < args.count {
            return URL(fileURLWithPath: args[idx + 1])
        }
        // 可执行文件所在目录
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        // 若位于 .app/Contents/MacOS/ 内，则上溯到 .app 的外层目录
        if dir.lastPathComponent == "MacOS" {
            dir = dir.deletingLastPathComponent()          // Contents
            if dir.lastPathComponent == "Contents" {
                dir = dir.deletingLastPathComponent()      // BubbleNote.app
                dir = dir.deletingLastPathComponent()      // bubble-note 根目录
            }
        }
        return dir.appendingPathComponent("message.txt")
    }

    func debugLog(_ s: String) {
        let line = "\(Date()) [\(s)]\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/bubble_note_debug.txt") {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.write(toFile: "/tmp/bubble_note_debug.txt", atomically: true, encoding: .utf8)
        }
    }

    override init() {
        messageURL = AppDelegate.resolveMessageURL()
        super.init()
        debugLog("1 AppDelegate.init, messageURL=\(messageURL.path)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("2 didFinish start")
        guard let screen = NSScreen.main else {
            debugLog("2b 无主屏幕, 退出")
            NSLog("BubbleNote: 无法获取主屏幕")
            NSApp.terminate(nil)
            return
        }
        debugLog("3 主屏 OK: \(screen.frame), visible=\(screen.visibleFrame), 屏幕数=\(NSScreen.screens.count)")
        let visible = screen.visibleFrame

        // 初始文案
        let initialText = loadText()

        // 创建气泡视图
        bubbleView = BubbleView(frame: .zero)
        bubbleView.text = initialText

        // 创建窗口（无边框、透明背景）
        let initialSize = BubbleView.measure(text: initialText)
        let origin = bottomRightOrigin(for: initialSize, in: visible)
        window = NSWindow(contentRect: NSRect(origin: origin, size: initialSize),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true
        window.contentView = bubbleView

        // 让窗口即使不激活也保持在最前（每 1 秒刷新一次层级）
        window.orderFrontRegardless()
        debugLog("4 窗口已创建并 orderFront: frame=\(window.frame), isVisible=\(window.isVisible)")

        if initialText.isEmpty {
            window.orderOut(nil)
        }
        lastContent = initialText
        writeState()

        // 防 App Nap：保持进程活跃，避免系统冻结文件监听
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "BubbleNote 需保持活跃以监听 message.txt 变化"
        )

        // 监听 message.txt 所在目录的文件变化（即时通道）
        startWatching(screen: screen)

        // 轮询兜底（每 2 秒检查内容，覆盖任何通知失效/文件替换场景）
        startPolling(screen: screen)

        NSLog("BubbleNote: 已启动，读取文案来自 %@", messageURL.path)
    }

    // MARK: 轮询兜底

    private func startPolling(screen: NSScreen) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reload(screen: screen)
        }
        // 加入 common mode，避免滚动等场景暂停
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    // MARK: 状态诊断（写入 /tmp/bubble_note_state.txt）

    func writeState() {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        let lines = [
            "时间: \(Date())",
            "窗口 frame: \(window.frame)",
            "窗口可见: \(window.isVisible)",
            "屏幕 frame: \(screen?.frame ?? .zero)",
            "屏幕 visibleFrame: \(screen?.visibleFrame ?? .zero)",
            "屏幕数: \(NSScreen.screens.count)",
            "文本长度: \(bubbleView.text.count)",
            "文本: \(bubbleView.text.prefix(50))",
        ]
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(toFile: "/tmp/bubble_note_state.txt", atomically: true, encoding: .utf8)
    }

    // MARK: 文本加载与刷新

    private func loadText() -> String {
        guard let raw = try? String(contentsOf: messageURL, encoding: .utf8) else {
            return ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc func reload(screen: NSScreen) {
        let text = loadText()
        guard let window, let bubbleView else { return }
        // 内容没变化则不重复刷新
        guard text != lastContent else { return }
        lastContent = text
        bubbleView.text = text
        let newSize = BubbleView.measure(text: text)
        let visible = screen.visibleFrame
        let newOrigin = bottomRightOrigin(for: newSize, in: visible)
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)

        if text.isEmpty {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
        writeState()
    }

    private func bottomRightOrigin(for size: NSSize, in visible: NSRect) -> NSPoint {
        // NSWindow 的坐标原点在屏幕左下角
        let x = visible.maxX - size.width - Config.rightMargin
        let y = visible.minY + Config.bottomMargin
        return NSPoint(x: x, y: y)
    }

    // MARK: 目录监听（保存文件时 inode 可能变化，监听目录最稳妥）

    private func startWatching(screen: NSScreen) {
        let dirPath = messageURL.deletingLastPathComponent().path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("BubbleNote: 无法打开目录 %@ 进行监听", dirPath)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reload(screen: screen)
        }
        source.setCancelHandler {
            close(fd)
        }
        dirSource = source
        source.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dirSource?.cancel()
        pollTimer?.invalidate()
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不占 Dock、无菜单栏
app.run()
