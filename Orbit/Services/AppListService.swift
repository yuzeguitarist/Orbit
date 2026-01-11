//
//  AppListService.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import Foundation

/// 获取和管理正在运行的应用列表
final class AppListService {
    static let shared = AppListService()
    private let iconCache = NSCache<NSString, NSImage>()

    private init() {
        iconCache.countLimit = 128
    }

    /// 获取当前正在运行的普通应用列表
    /// - Parameter excludingProcessIdentifier: 需要排除的进程 ID（如当前前台应用）
    func getRunningApps(excludingProcessIdentifier: pid_t? = nil) -> [AppInfo] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let activePid: pid_t? = {
            if let excludingProcessIdentifier {
                return excludingProcessIdentifier
            }
            guard let activeApp = runningApps.first(where: { $0.isActive }) else {
                return nil
            }
            guard WindowVisibilityChecker.hasVisibleWindow(processIdentifier: activeApp.processIdentifier) else {
                return nil
            }
            return activeApp.processIdentifier
        }()

        var apps: [AppInfo] = []

        for app in runningApps {
            // 只显示普通应用（有 UI 的应用）
            guard app.activationPolicy == .regular else { continue }
            // 排除自己
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            // 排除当前前台应用
            if let excludePid = activePid, app.processIdentifier == excludePid {
                continue
            }

            let bundleId = app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier)
            let name = app.localizedName ?? "Unknown"
            let cacheKey = bundleId as NSString
            let cachedIcon = iconCache.object(forKey: cacheKey)
            let icon = cachedIcon
                ?? app.icon
                ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                ?? NSImage()

            if cachedIcon == nil {
                iconCache.setObject(icon, forKey: cacheKey)
            }

            let appInfo = AppInfo(
                id: bundleId,
                name: name,
                icon: icon,
                bundleURL: app.bundleURL,
                processIdentifier: app.processIdentifier
            )
            apps.append(appInfo)
        }

        return apps
    }
}
