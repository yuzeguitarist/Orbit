//
//  OrbitWindow.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import SwiftUI

/// 自定义透明面板
class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
    }
}

/// 文件拖拽容器视图 - 包装 SwiftUI 内容并处理文件拖拽
class DragDropContainerView: NSView {
    /// 文件拖拽代理
    weak var fileDragDelegate: FileDragDelegate?

    /// 窗口中心位置（用于判断是否在中心区域）
    var viewCenter: CGPoint {
        CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 注册接受文件拖拽
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        print("DragDropContainerView: draggingEntered called")
        guard let urls = extractFileURLs(from: sender), !urls.isEmpty else {
            print("DragDropContainerView: No valid file URLs found")
            return []
        }

        print("DragDropContainerView: Found \(urls.count) file(s): \(urls)")
        fileDragDelegate?.fileDragEntered(urls: urls)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let isOverCenter = isLocationOverCenter(location)
        fileDragDelegate?.fileDragUpdated(location: location, isOverCenter: isOverCenter)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        print("DragDropContainerView: draggingExited called")
        fileDragDelegate?.fileDragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        print("DragDropContainerView: performDragOperation called")
        guard let urls = extractFileURLs(from: sender), !urls.isEmpty else {
            return false
        }

        let location = convert(sender.draggingLocation, from: nil)
        let isOverCenter = isLocationOverCenter(location)
        return fileDragDelegate?.fileDragPerformed(urls: urls, location: location, isOverCenter: isOverCenter) ?? false
    }

    // MARK: - Helpers

    private func extractFileURLs(from info: any NSDraggingInfo) -> [URL]? {
        let pasteboard = info.draggingPasteboard

        guard let items = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }

        let fileURLs = items.filter { $0.isFileURL }
        return fileURLs.isEmpty ? nil : fileURLs
    }

    private func isLocationOverCenter(_ location: CGPoint) -> Bool {
        let dx = location.x - viewCenter.x
        let dy = location.y - viewCenter.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance < OrbitConfig.centerDropRadius
    }
}

/// 文件拖拽代理协议
protocol FileDragDelegate: AnyObject {
    func fileDragEntered(urls: [URL])
    func fileDragUpdated(location: CGPoint, isOverCenter: Bool)
    func fileDragExited()
    func fileDragPerformed(urls: [URL], location: CGPoint, isOverCenter: Bool) -> Bool
}

/// 取消或重新展示后，旧的提交与动画回调不能继续操作圆环。
struct OrbitDismissalState {
    private(set) var presentationID = UUID()
    private(set) var isShowing = false
    private(set) var isDismissing = false
    private var isCommitPending = false

    mutating func begin() {
        presentationID = UUID()
        isShowing = true
        isDismissing = false
        isCommitPending = false
    }

    mutating func beginCommit() -> UUID? {
        guard isShowing, !isDismissing, !isCommitPending else { return nil }
        isCommitPending = true
        return presentationID
    }

    func acceptsCompletion(for id: UUID) -> Bool {
        isShowing && presentationID == id
    }

    mutating func beginDismissal() -> UUID? {
        guard isShowing, !isDismissing else { return nil }
        presentationID = UUID()
        isCommitPending = false
        isDismissing = true
        return presentationID
    }

    mutating func close() {
        presentationID = UUID()
        isShowing = false
        isDismissing = false
        isCommitPending = false
    }
}

/// Orbit 弹窗控制器
final class OrbitWindowController: NSObject, FileDragDelegate {
    static let shared = OrbitWindowController()

    private var panel: OrbitPanel?
    private var dragDropContainer: DragDropContainerView?
    private let ringCoordinator = OrbitRingCoordinator()
    private var localEventMonitor: Any?
    private var toggleObserver: Any?
    private var cycleObserver: Any?
    private var dismissalState = OrbitDismissalState()
    private var isShowing: Bool { dismissalState.isShowing }
    private var isDismissing: Bool { dismissalState.isDismissing }
    private var previousFrontmostApp: NSRunningApplication?
    private var shouldRestorePreviousAppOnClose = false
    /// 剪贴板模式下松开触发键：关闭并切回原 App 后发送 ⌘V（Deck #166）。
    private var shouldPasteAfterClose = false
    private var presentationID: UUID { dismissalState.presentationID }

    private override init() {
        super.init()
    }

    @MainActor
    func show(at mousePosition: CGPoint, autoSelectFirstApp: Bool = false) {
        guard !isShowing else { return }
        dismissalState.begin()

        let context = currentContext()
        let anchorPosition = anchorPosition(for: mousePosition)
        NSApp.activate(ignoringOtherApps: true)
        ringCoordinator.prepareForShow(
            at: anchorPosition,
            contextAppId: context.appId,
            excludingProcessIdentifier: context.processIdentifier,
            autoSelectFirstApp: autoSelectFirstApp
        )

        guard ringCoordinator.appViewModel.appCount > 0 else {
            dismissImmediately()
            return
        }

        createPanel(anchorPosition: anchorPosition)
        setupEventMonitors()

        print("OrbitWindowController: Showing with \(ringCoordinator.appViewModel.appCount) apps")
    }

    /// 显示窗口用于文件拖拽（无需应用列表）
    @MainActor
    func showForFileDrag(at mousePosition: CGPoint) {
        guard !isShowing else { return }
        dismissalState.begin()

        let context = currentContext()
        let anchorPosition = anchorPosition(for: mousePosition)
        NSApp.activate(ignoringOtherApps: true)
        ringCoordinator.prepareForShow(
            at: anchorPosition,
            contextAppId: context.appId,
            excludingProcessIdentifier: context.processIdentifier
        )
        createPanel(anchorPosition: anchorPosition)
        setupEventMonitors()

        print("OrbitWindowController: Showing for file drag")
    }

    @MainActor
    func hide(activateSelected: Bool = false) {
        guard isShowing else { return }
        guard activateSelected else {
            dismissImmediately()
            return
        }
        guard !ringCoordinator.isTransitioning else {
            dismissImmediately()
            return
        }
        guard let currentPresentationID = dismissalState.beginCommit() else { return }

        if ringCoordinator.mode == .apps {
            let activated = ringCoordinator.appViewModel.activateSelectedApp()
            shouldRestorePreviousAppOnClose = !activated
            if !activated, HotKeyService.shared.dismissStyle == .animated {
                dismissAnimated()
            } else {
                closePanel()
            }
        } else {
            // 剪贴板模式：先写入剪贴板，再关闭并粘贴到原来的 App。
            ringCoordinator.clipboardViewModel.copySelectedItem { [weak self] success in
                Task { @MainActor in
                    guard let self, self.dismissalState.acceptsCompletion(for: currentPresentationID) else { return }
                    self.shouldPasteAfterClose = success
                    self.shouldRestorePreviousAppOnClose = true
                    if HotKeyService.shared.dismissStyle == .animated {
                        self.startCloseAnimation()
                    } else {
                        self.closePanel()
                    }
                }
            }
        }
    }

    @MainActor
    func dismissImmediately() {
        guard isShowing else { return }
        shouldPasteAfterClose = false
        shouldRestorePreviousAppOnClose = true
        closePanel()
    }

    @MainActor
    func dismissAnimated() {
        guard isShowing else { return }
        shouldPasteAfterClose = false
        shouldRestorePreviousAppOnClose = true
        HotKeyService.shared.notifyOrbitDismissed()
        startCloseAnimation()
    }

    @MainActor
    private func startCloseAnimation() {
        guard let currentPresentationID = dismissalState.beginDismissal() else { return }

        if ringCoordinator.isTransitioning {
            closePanel()
            return
        }

        let speed = OrbitConfig.dismissCollapseSpeed
        switch ringCoordinator.mode {
        case .apps:
            ringCoordinator.appViewModel.startCollapseAnimation(speed: speed) { [weak self] in
                Task { @MainActor in
                    guard let self, self.dismissalState.acceptsCompletion(for: currentPresentationID) else { return }
                    self.closePanel()
                }
            }
        case .clipboard:
            ringCoordinator.clipboardViewModel.startCollapseAnimation(speed: speed) { [weak self] in
                Task { @MainActor in
                    guard let self, self.dismissalState.acceptsCompletion(for: currentPresentationID) else { return }
                    self.closePanel()
                }
            }
        }
    }

    @MainActor
    private func createPanel(anchorPosition: CGPoint) {
        let screen = screenForPoint(anchorPosition)

        // 窗口大小根据应用数量动态调整
        let appCount = min(ringCoordinator.appViewModel.appCount, OrbitConfig.maxVisibleCards)
        let maxCount = max(appCount, ClipboardRingViewModel.maxVisibleCards)
        let size = ArcLayout.windowSize(forAppCount: max(maxCount, 6)) // 至少保证一定大小
        let windowSize = CGSize(width: size, height: size)

        let windowOrigin = NSPoint(
            x: anchorPosition.x - windowSize.width / 2,
            y: anchorPosition.y - windowSize.height / 2
        )
        let screenFrame = screen.visibleFrame
        let clampedOrigin = NSPoint(
            x: windowSize.width >= screenFrame.width
                ? screenFrame.minX
                : min(max(windowOrigin.x, screenFrame.minX), screenFrame.maxX - windowSize.width),
            y: windowSize.height >= screenFrame.height
                ? screenFrame.minY
                : min(max(windowOrigin.y, screenFrame.minY), screenFrame.maxY - windowSize.height)
        )

        let panel = OrbitPanel(
            contentRect: NSRect(origin: clampedOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Orbit"
        panel.setAccessibilityIdentifier("orbit.ring")

        // 创建拖拽容器视图
        let containerView = DragDropContainerView(frame: NSRect(origin: .zero, size: windowSize))
        containerView.fileDragDelegate = self
        containerView.autoresizingMask = [.width, .height]

        // 创建 SwiftUI 托管视图
        let hostingView = NSHostingView(
            rootView: OrbitRingContainerView(
                coordinator: ringCoordinator,
                onCommit: { [weak self] in
                    self?.hide(activateSelected: true)
                },
                onCancel: { [weak self] in
                    self?.hide(activateSelected: false)
                }
            )
        )
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]

        // 将托管视图添加到容器中
        containerView.addSubview(hostingView)

        // 设置容器为窗口内容视图
        panel.contentView = containerView

        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.dragDropContainer = containerView
    }

    private func anchorPosition(for mousePosition: CGPoint) -> CGPoint {
        guard OrbitConfig.lockRingToScreenCenter else { return mousePosition }
        let screen = screenForPoint(mousePosition)
        let screenFrame = screen.visibleFrame
        return CGPoint(x: screenFrame.midX, y: screenFrame.midY)
    }

    private func screenForPoint(_ point: CGPoint) -> NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        } ?? NSScreen.main ?? NSScreen.screens.first!
    }

    private func currentContext() -> (appId: String?, processIdentifier: pid_t?) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            previousFrontmostApp = nil
            return (nil, nil)
        }

        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            previousFrontmostApp = nil
            return (nil, nil)
        }

        previousFrontmostApp = frontmost
        let appId = AppListService.appIdentifier(for: frontmost)
        return (appId, frontmost.processIdentifier)
    }

    private func closePanel() {
        dismissalState.close()
        let shouldRestorePreviousApp = shouldRestorePreviousAppOnClose
        shouldRestorePreviousAppOnClose = false
        let shouldPaste = shouldPasteAfterClose
        shouldPasteAfterClose = false
        let appToRestore = previousFrontmostApp
        previousFrontmostApp = nil
        removeEventMonitors()
        ringCoordinator.resetAfterDismiss()
        panel?.orderOut(nil)
        panel = nil
        dragDropContainer = nil
        HotKeyService.shared.notifyOrbitDismissed()
        if shouldRestorePreviousApp {
            restorePreviousFrontmostApp(appToRestore)
        }
        if shouldPaste {
            postPasteShortcut(to: appToRestore)
        }
    }

    /// 等原 App 重新激活后再发送 ⌘V。
    private func postPasteShortcut(to app: NSRunningApplication?) {
        guard AXIsProcessTrusted(), let app else { return }
        let closedPresentationID = presentationID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.presentationID == closedPresentationID, !self.isShowing,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let source = CGEventSource(stateID: .privateState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func restorePreviousFrontmostApp(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if app.isHidden {
            app.unhide()
        }
        if #available(macOS 14.0, *) {
            _ = app.activate(options: [.activateAllWindows])
        } else {
            _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    // MARK: - FileDragDelegate

    func fileDragEntered(urls: [URL]) {
        Task { @MainActor in
            ringCoordinator.appViewModel.handleFileDragEntered(urls: urls)
        }
    }

    func fileDragUpdated(location: CGPoint, isOverCenter: Bool) {
        Task { @MainActor in
            ringCoordinator.appViewModel.handleFileDragUpdated(isOverCenter: isOverCenter)
        }
    }

    func fileDragExited() {
        Task { @MainActor in
            ringCoordinator.appViewModel.handleFileDragExited()
        }
    }

    func fileDragPerformed(urls: [URL], location: CGPoint, isOverCenter: Bool) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                ringCoordinator.appViewModel.handleFileDragPerformed()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                ringCoordinator.appViewModel.handleFileDragPerformed()
            }
        }
    }

    private func setupEventMonitors() {
        if toggleObserver == nil {
            toggleObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OrbitToggleMode"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isShowing, !self.isDismissing else { return }
                    self.ringCoordinator.toggleMode()
                }
            }
        }

        if cycleObserver == nil {
            cycleObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OrbitCycleSelection"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let direction = notification.userInfo?["direction"] as? String
                MainActor.assumeIsolated {
                    guard let self, self.isShowing, !self.isDismissing else { return }
                    switch self.ringCoordinator.mode {
                    case .apps:
                        if direction == "previous" {
                            self.ringCoordinator.appViewModel.selectPrevious()
                        } else {
                            self.ringCoordinator.appViewModel.selectNext()
                        }
                    case .clipboard:
                        if direction == "previous" {
                            self.ringCoordinator.clipboardViewModel.selectPrevious()
                        } else {
                            self.ringCoordinator.clipboardViewModel.selectNext()
                        }
                    }
                }
            }
        }

        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleKeyEvent(event)
                return nil
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isShowing else { return }
        switch ringCoordinator.mode {
        case .apps:
            handleAppKeyEvent(event)
        case .clipboard:
            handleClipboardKeyEvent(event)
        }
    }

    private func handleAppKeyEvent(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            hide(activateSelected: false)
            return
        }

        if event.keyCode == 36 { // Enter
            hide(activateSelected: true)
            return
        }

        let result = ringCoordinator.appViewModel.handleKeyPress(
            event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
        if result == .activateAndDismiss {
            hide(activateSelected: true)
        }
    }

    private func handleClipboardKeyEvent(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            hide(activateSelected: false)
            return
        }

        if event.keyCode == 36 { // Enter
            hide(activateSelected: true)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            ringCoordinator.clipboardViewModel.deleteSelectedItem()
            return
        }

        if let characters = event.charactersIgnoringModifiers?.lowercased(),
           characters == "c"
        {
            let currentPresentationID = presentationID
            ringCoordinator.clipboardViewModel.copySelectedItem { [weak self] success in
                guard success else { return }
                Task { @MainActor in
                    guard let self else { return }
                    guard self.presentationID == currentPresentationID else { return }
                    self.hide(activateSelected: false)
                }
            }
            return
        }

        _ = ringCoordinator.clipboardViewModel.handleKeyPress(
            event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    private func removeEventMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let observer = toggleObserver {
            NotificationCenter.default.removeObserver(observer)
            toggleObserver = nil
        }
        if let observer = cycleObserver {
            NotificationCenter.default.removeObserver(observer)
            cycleObserver = nil
        }
    }
}

/// 主视图
struct OrbitMainView: View {
    @ObservedObject var hotKeyService = HotKeyService.shared
    @State private var hasPermission = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Orbit")
                .font(.largeTitle)
                .fontWeight(.bold)

            if hasPermission {
                VStack(spacing: 8) {
                    Label(
                        OrbitConfig.triggerHelpText(
                            longPressKey: "main.help.trigger",
                            shortcutKey: "main.help.trigger.custom",
                            disabledKey: "main.help.trigger.disabled"
                        ),
                        systemImage: "keyboard"
                    )
                        .foregroundColor(.secondary)

                    Text("main.help.hint")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                VStack(spacing: 12) {
                    Text("main.permission.required")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Text("main.permission.details")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("main.permission.open_settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("main.permission.check") {
                        checkPermission()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(40)
        .frame(minWidth: 300, minHeight: 250)
        .onAppear {
            checkPermission()
        }
        .onChange(of: hotKeyService.shouldShowOrbit) { _, shouldShow in
            if shouldShow {
                Task { @MainActor in
                    OrbitWindowController.shared.show(at: hotKeyService.mouseLocation)
                }
            } else {
                Task { @MainActor in
                    if hotKeyService.shouldActivateOnDismiss {
                        OrbitWindowController.shared.hide(activateSelected: true)
                    } else if hotKeyService.dismissStyle == .animated {
                        OrbitWindowController.shared.dismissAnimated()
                    } else {
                        OrbitWindowController.shared.dismissImmediately()
                    }
                }
            }
        }
    }

    private func checkPermission() {
        hasPermission = HotKeyService.checkAccessibilityPermission()
        if hasPermission {
            hotKeyService.startListening()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
