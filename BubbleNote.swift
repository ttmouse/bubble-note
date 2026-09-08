//
//  BubbleNote.swift
//  右下角气泡备忘展示工具
//
//  功能：
//    - 在 Mac 屏幕右下角弹出一个置顶的深色圆角气泡机器人
//    - 内容读取自同目录的 message.txt；表情读取自 emotion.txt（一行颜文字）
//    - emotion.txt 不存在/为空时：机器人自主随机切换表情（像活物一样）
//    - 实时监听文件变化自动更新，无需重启
//    - 点击气泡可临时隐藏（像受惊小动物躲起来），内容更新后自动重新出现
//
//  用法：
//    构建：  ./build.sh
//    启动：  ./start.sh          （或直接 ./BubbleNote）
//    停止：  ./stop.sh
//    换内容/换表情：note 命令（见 README），如 note --happy 快去开会
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
    /// 表情行字号（颜文字，比正文更大更突出）
    static let emotionFontSize: CGFloat = 40
    /// 表情行颜色（科技感的亮青色）
    static let emotionColor = NSColor(calibratedRed: 0.42, green: 0.95, blue: 0.85, alpha: 1.0)
    /// 文本阴影
    static let hasTextShadow = true
    /// 是否支持点击气泡临时隐藏；false 则保持鼠标点击穿透
    static let clickToDismiss = true
    /// 躲藏动画：被点击后先向上轻跳的时长（秒）
    static let hopDuration: TimeInterval = 0.13
    /// 躲藏动画：溜出屏幕躲起来的时长（秒）
    static let runAwayDuration: TimeInterval = 0.30
    /// 躲藏动画：起跳高度（pt）
    static let hopHeight: CGFloat = 16
    /// 自主随机表情池（emotion.txt 为空时，机器人像活物一样自行换表情）
    static let aliveFaces: [String] = [
        "(•‿•)",      // 开心
        "(•̀ᴗ•́)و",    // 元气
        "(◕‿◕)",      // 满足
        "(-‿-)",      // 眯眯眼
        "(￣▽￣)",    // 得意
        "(¬‿¬)",      // 调皮
        "(•_•)",      // 淡定
        "(⊙_⊙)",      // 惊讶
        "(￣～￣)",    // 撇嘴思考
        "(•_•)?",     // 疑惑
        "(￣□￣)",    // 呆住
        "(｡•̀ᴗ-)✧",   // 眨眼
        "(︶︹︺)",    // 无奈
        "(T_T)",      // 委屈
        "zZ(-_-)",    // 犯困
    ]
    /// 自主模式下两次随机换脸的间隔范围（秒）
    static let aliveIntervalRange: ClosedRange<Double> = 6...14
}

// MARK: - 气泡视图（自绘圆角背景 + 文本标签）

final class BubbleView: NSView {

    let label = NSTextField(labelWithString: "")
    var text: String = "" {
        didSet { refresh() }
    }
    /// 表情行（颜文字），为空则不显示
    var emotion: String = "" {
        didSet { refresh() }
    }
    /// 点击气泡任意位置时回调（由 AppDelegate 绑定为关闭动作）
    var onClick: (() -> Void)?

    // 窗口未激活时首次点击也直接交给视图（否则第一次点击只被用于激活）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
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
        label.attributedStringValue = BubbleView.attributed(emotion: emotion, text: text)
        needsDisplay = true
    }

    // MARK: 富文本组装（表情行 + 正文）

    static func attributed(emotion: String, text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if !emotion.isEmpty {
            let ep = NSMutableParagraphStyle()
            ep.alignment = .center
            ep.lineSpacing = 2
            ep.lineBreakMode = .byCharWrapping
            result.append(NSAttributedString(string: emotion + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: Config.emotionFontSize, weight: .bold),
                .foregroundColor: Config.emotionColor,
                .paragraphStyle: ep,
                .shadow: bubbleTextShadow()
            ]))
        }

        if !text.isEmpty {
            let tp = NSMutableParagraphStyle()
            tp.lineSpacing = 4
            tp.lineBreakMode = .byCharWrapping
            result.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: Config.fontSize, weight: .medium),
                .foregroundColor: Config.textColor,
                .paragraphStyle: tp,
                .shadow: bubbleTextShadow()
            ]))
        }
        return result
    }

    static func bubbleTextShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    // MARK: 文本测量（宽度永远不超过 maxWidth，超长则增高换行）

    static func measure(emotion: String, text: String) -> NSSize {
        guard !(emotion.isEmpty && text.isEmpty) else { return .zero }
        let attrStr = attributed(emotion: emotion, text: text)
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
    var emotionURL: URL
    var dirSource: DispatchSourceFileSystemObject?
    var pollTimer: Timer?
    private var lastContent: String = ""
    /// 用户点击关闭后为 true：保持隐藏，直到 message.txt 内容更新或重新写入
    private var dismissed = false
    /// emotion.txt 有内容时的锁定表情；nil = 未锁定，机器人自主随机
    private var lockedFace: String? = nil
    /// 当前实际显示的表情（锁定表情或自主随机脸）
    private var currentFace: String = ""
    /// 上次读取的 emotion.txt 内容（用于检测"解除锁定"）
    private var lastFileEmotion: String = ""
    /// 自主随机换脸定时器
    private var aliveTimer: Timer?
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
        emotionURL = messageURL.deletingLastPathComponent().appendingPathComponent("emotion.txt")
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

        // 初始文案与表情
        let initialText = loadText()
        let initialEmotion = loadEmotion()
        lastFileEmotion = initialEmotion
        if !initialEmotion.isEmpty {
            lockedFace = initialEmotion
            currentFace = initialEmotion
        } else {
            lockedFace = nil
            currentFace = Config.aliveFaces.randomElement() ?? ""
        }

        // 创建气泡视图
        bubbleView = BubbleView(frame: .zero)
        bubbleView.text = initialText
        bubbleView.emotion = currentFace

        // 创建窗口（无边框、透明背景）
        let initialSize = BubbleView.measure(emotion: currentFace, text: initialText)
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
        window.ignoresMouseEvents = !Config.clickToDismiss
        window.contentView = bubbleView

        if Config.clickToDismiss {
            // 点击气泡任意位置 → 临时隐藏（内容更新后自动恢复显示）
            bubbleView.onClick = { [weak self] in
                self?.dismissBubble()
            }
        }

        // 让窗口即使不激活也保持在最前（每 1 秒刷新一次层级）
        window.orderFrontRegardless()
        debugLog("4 窗口已创建并 orderFront: frame=\(window.frame), isVisible=\(window.isVisible)")

        if initialText.isEmpty {
            window.orderOut(nil)
        }
        lastContent = initialEmotion + "\u{0}" + initialText
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

        // 自主随机表情（emotion.txt 未锁定时生效）
        startAliveTimer()

        NSLog("BubbleNote: 已启动，读取文案来自 %@", messageURL.path)
    }

    // MARK: 自主随机表情（活物感）

    private func startAliveTimer() {
        scheduleAliveTick()
    }

    private func scheduleAliveTick() {
        aliveTimer?.invalidate()
        let delay = Double.random(in: Config.aliveIntervalRange)
        aliveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.aliveTick()
        }
    }

    private func aliveTick() {
        defer { scheduleAliveTick() }   // 无论是否换脸都继续循环
        guard let window, window.isVisible, !dismissed, lockedFace == nil else { return }
        let face = randomFace(differentFrom: currentFace)
        guard face != currentFace, let bubbleView else { return }
        currentFace = face
        bubbleView.emotion = face
        applyLayout(on: window.screen ?? NSScreen.main)
        writeState()
    }

    private func randomFace(differentFrom current: String) -> String {
        let pool = Config.aliveFaces
        guard pool.count > 1 else { return current }
        var face = pool.randomElement() ?? current
        var tries = 0
        while face == current && tries < 5 {
            face = pool.randomElement() ?? current
            tries += 1
        }
        return face
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
            "当前表情: \(bubbleView.emotion)",
            "表情锁定: \(lockedFace ?? "无(自主随机)")",
            "用户已点击关闭: \(dismissed)",
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

    private func loadEmotion() -> String {
        guard let raw = try? String(contentsOf: emotionURL, encoding: .utf8) else {
            return ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// reawaken=true 表示这次刷新由真实的文件写入事件触发：
    /// 用户手动关闭（dismissed）后，只要 message.txt 被重新写入就恢复显示，
    /// 即使是相同内容；轮询兜底则不会把已关闭的气泡又弹回来。
    func reload(screen: NSScreen, reawaken: Bool = false) {
        let text = loadText()
        let fileEmotion = loadEmotion()

        // 更新表情锁定状态：emotion.txt 非空则锁定该表情；被清空则恢复自主随机
        if !fileEmotion.isEmpty {
            lockedFace = fileEmotion
            currentFace = fileEmotion
        } else if !lastFileEmotion.isEmpty {
            lockedFace = nil
            currentFace = randomFace(differentFrom: currentFace)
        } else {
            lockedFace = nil
        }
        lastFileEmotion = fileEmotion

        let key = fileEmotion + "\u{0}" + text
        guard let window, let bubbleView else { return }

        if dismissed {
            // 已被用户点击关闭：内容为空则继续保持隐藏
            if text.isEmpty && fileEmotion.isEmpty { return }
            // 仅内容变化或收到新的写入事件时才恢复显示（轮询兜底不把已关闭的气泡弹回）
            if !reawaken && key == lastContent { return }
            dismissed = false
            // 即使是相同内容被重新写入，也要重新弹出
            if key == lastContent {
                resetAppearance()
                bubbleView.emotion = currentFace
                window.orderFrontRegardless()
                writeState()
                return
            }
        }

        // 内容没变化则不重复刷新
        guard key != lastContent else { return }
        lastContent = key
        bubbleView.emotion = currentFace
        bubbleView.text = text
        applyLayout(on: screen)

        if text.isEmpty {
            window.orderOut(nil)
        } else {
            // 新内容显示前复位图层（可能正处于消散动画的半透明/缩小状态）
            resetAppearance()
            window.orderFrontRegardless()
        }
        writeState()
    }

    /// 依据当前显示的表情与文本重新计算窗口大小并摆回右下角
    private func applyLayout(on screen: NSScreen?) {
        guard let window, let bubbleView,
              let screen = screen ?? NSScreen.main else { return }
        let newSize = BubbleView.measure(emotion: bubbleView.emotion, text: bubbleView.text)
        let visible = screen.visibleFrame
        let newOrigin = bottomRightOrigin(for: newSize, in: visible)
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
    }

    /// 用户点击气泡 → 让它像受惊的小动物一样先轻快地蹦一下，
    /// 再「嗖」地溜出屏幕底边躲起来；不清空 message.txt，文案更新后自动恢复
    func dismissBubble() {
        guard let window, window.isVisible, !dismissed else { return }
        dismissed = true
        debugLog("用户点击，气泡准备溜走躲起来")
        let from = window.frame
        // 第一段：被点到，先向上一蹦（easeOut，起跳轻快）
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Config.hopDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(NSPoint(x: from.origin.x,
                                                     y: from.origin.y + Config.hopHeight))
        }, completionHandler: { [weak self] in
            self?.runAwayAndHide()
        })
    }

    /// 第二段：从起跳点斜向加速滑出屏幕底边躲起来，身影同时淡出
    private func runAwayAndHide() {
        // 若在起跳动画期间已被新内容唤起，就不再溜走（位置由 reload 摆回）
        guard let window, dismissed else { return }
        let current = window.frame
        // 完全滑出屏幕底边（y 为负）并向右斜窜一点，像跑到屏幕外躲起来
        let hide = NSPoint(x: current.minX + 26, y: -current.height - 10)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Config.runAwayDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrameOrigin(hide)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.finishRunaway()
        })
    }

    private func finishRunaway() {
        guard let window else { return }
        resetAppearance()
        if dismissed {
            window.orderOut(nil)
            debugLog("用户点击，气泡已溜走躲起来（message.txt 更新后重新出现）")
        } else {
            // 动画期间内容已被更新唤起：保持显示
            window.orderFrontRegardless()
        }
        writeState()
    }

    /// 复位窗口外观（透明度和动画残留），供下次重新出现时使用；frame 由 reload 重新摆放
    private func resetAppearance() {
        guard let window else { return }
        window.alphaValue = 1.0
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
            self?.reload(screen: screen, reawaken: true)
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
        aliveTimer?.invalidate()
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
