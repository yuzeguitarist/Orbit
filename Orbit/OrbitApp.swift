//
//  OrbitApp.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Debug toggle for Welcome View
    static let debugShowWelcome = false
    
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// 应用代理 - 菜单栏应用
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为后台应用（无 Dock 图标）
        NSApp.setActivationPolicy(.accessory)

        // 创建菜单栏图标
        setupStatusItem()

        // 检查并启动键盘监听
        if HotKeyService.checkAccessibilityPermission() {
            HotKeyService.shared.startListening()
        }

        // 监听显示状态变化
        setupOrbitObserver()
        
        // Check for Welcome View
        // Use a short delay to ensure app is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if OrbitApp.debugShowWelcome || !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
                WelcomeWindowController.shared.show()
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyService.shared.stopListening()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // 使用 SF Symbol 作为菜单栏图标
            button.image = NSImage(systemSymbolName: "circle.hexagongrid.circle", accessibilityDescription: "Orbit")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            // 右键显示菜单
            showMenu()
        } else {
            // 左键显示状态/帮助
            showMenu()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        // 权限状态
        let hasPermission = HotKeyService.checkAccessibilityPermission()
        let statusTitle = hasPermission
            ? NSLocalizedString("menu.permission.enabled", comment: "")
            : NSLocalizedString("menu.permission.required", comment: "")
        let permissionItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())

        // 使用说明
        let helpTitle = String(
            format: NSLocalizedString("menu.help.trigger", comment: ""),
            OrbitConfig.triggerModifier.symbol
        )
        let helpItem = NSMenuItem(title: helpTitle, action: nil, keyEquivalent: "")
        helpItem.isEnabled = false
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        if !hasPermission {
            menu.addItem(NSMenuItem(
                title: NSLocalizedString("menu.accessibility.authorize", comment: ""),
                action: #selector(openAccessibility),
                keyEquivalent: ""
            ))
        }

        menu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.settings", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: ""),
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupOrbitObserver() {
        // 监听 shouldShowOrbit 变化
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OrbitShouldShow"),
            object: nil,
            queue: .main
        ) { notification in
            if let shouldShow = notification.userInfo?["show"] as? Bool {
                if shouldShow {
                    let location = notification.userInfo?["location"] as? CGPoint ?? NSEvent.mouseLocation
                    Task { @MainActor in
                        OrbitWindowController.shared.show(at: location)
                    }
                } else {
                    let shouldActivate = notification.userInfo?["activate"] as? Bool ?? false
                    Task { @MainActor in
                        if shouldActivate {
                            OrbitWindowController.shared.hide(activateSelected: true)
                        } else {
                            OrbitWindowController.shared.dismissImmediately()
                        }
                    }
                }
            }
        }
    }
}

/// 设置窗口控制器
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = NSLocalizedString("settings.title", comment: "")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 设置视图
struct SettingsView: View {
    @State private var longPressThreshold: Double = OrbitConfig.longPressThreshold
    @State private var triggerModifier: TriggerModifier = OrbitConfig.triggerModifier
    @State private var cardSize: CardSize = OrbitConfig.cardSize
    @State private var cardMaterial: OrbitConfig.CardMaterial = OrbitConfig.cardMaterial
    @State private var hasPermission = HotKeyService.checkAccessibilityPermission()
    @State private var launchAtLoginEnabled = false
    @State private var isLaunchAtLoginSupported = LaunchAtLoginManager.isSupported

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasPermission ? .green : .orange)
                    Text(hasPermission ? "settings.permission.granted" : "settings.permission.required")
                    Spacer()
                    if !hasPermission {
                        Button("settings.permission.authorize") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section("settings.section.trigger") {
                Picker("settings.trigger.modifier", selection: $triggerModifier) {
                    ForEach(TriggerModifier.allCases) { modifier in
                        Text(modifier.localizedName).tag(modifier)
                    }
                }

                HStack {
                    Text("settings.trigger.threshold")
                    Slider(value: $longPressThreshold, in: 100 ... 300, step: 10)
                    Text(String(
                        format: NSLocalizedString("settings.long_press_value", comment: ""),
                        Int(longPressThreshold)
                    ))
                        .frame(width: 55)
                        .monospacedDigit()
                }
                .onChange(of: longPressThreshold) { _, newValue in
                    OrbitConfig.longPressThreshold = newValue
                }
                .onChange(of: triggerModifier) { _, newValue in
                    OrbitConfig.triggerModifier = newValue
                }
            }

            Section("settings.section.appearance") {
                Picker("settings.card_size", selection: $cardSize) {
                    ForEach(CardSize.allCases, id: \.self) { size in
                        Text(size.localizedName).tag(size)
                    }
                }
                .onChange(of: cardSize) { _, newValue in
                    OrbitConfig.cardSize = newValue
                }

                Picker("settings.card_material", selection: $cardMaterial) {
                    ForEach(OrbitConfig.CardMaterial.allCases) { material in
                        Text(material.localizedName).tag(material)
                    }
                }
                .onChange(of: cardMaterial) { _, newValue in
                    OrbitConfig.cardMaterial = newValue
                }
            }

            Section("settings.section.launch") {
                if isLaunchAtLoginSupported {
                    Toggle("settings.launch_at_login", isOn: $launchAtLoginEnabled)
                        .onChange(of: launchAtLoginEnabled) { _, newValue in
                            do {
                                try LaunchAtLoginManager.setEnabled(newValue)
                            } catch {
                                launchAtLoginEnabled = LaunchAtLoginManager.refreshStatus()
                            }
                        }
                } else {
                    Text("settings.launch_at_login.unsupported")
                        .foregroundColor(.secondary)
                }
            }

            Section("settings.section.usage") {
                Text(String(
                    format: NSLocalizedString("settings.usage.line1", comment: ""),
                    triggerModifier.symbol
                ))
                Text("settings.usage.line2")
                Text("settings.usage.line3")
                Text("settings.usage.line4")
            }
            .foregroundColor(.secondary)
            .font(.callout)
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 430)
        .onAppear {
            hasPermission = HotKeyService.checkAccessibilityPermission()
            longPressThreshold = OrbitConfig.longPressThreshold
            triggerModifier = OrbitConfig.triggerModifier
            cardSize = OrbitConfig.cardSize
            cardMaterial = OrbitConfig.cardMaterial
            isLaunchAtLoginSupported = LaunchAtLoginManager.isSupported
            if isLaunchAtLoginSupported {
                launchAtLoginEnabled = LaunchAtLoginManager.refreshStatus()
            }
        }
    }
}
