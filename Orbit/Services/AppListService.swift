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
    private let fallbackIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()

    private init() {
        iconCache.countLimit = 64
        iconCache.totalCostLimit = 24 * 1024 * 1024
    }

    static func appIdentifier(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier)
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

            let appId = AppListService.appIdentifier(for: app)
            let name = app.localizedName ?? "Unknown"

            let appInfo = AppInfo(
                id: appId,
                name: name,
                bundleURL: app.bundleURL,
                processIdentifier: app.processIdentifier
            )
            apps.append(appInfo)
        }

        return apps
    }

    func icon(forAppId appId: String, processIdentifier: pid_t, bundleURL: URL?) -> NSImage {
        let cacheKey = appId as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }

        let preparedImage = autoreleasepool { () -> NSImage in
            let sourceIcon = NSRunningApplication(processIdentifier: processIdentifier)?.icon
                ?? bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? fallbackIcon
            return makePreparedIcon(from: sourceIcon)
        }
        iconCache.setObject(preparedImage, forKey: cacheKey, cost: cacheCost(for: preparedImage))
        return preparedImage
    }

    private func makePreparedIcon(from image: NSImage) -> NSImage {
        let targetDimension = min(max(CardSize.extraLarge.iconSize * 2, 96), 128)
        let targetSize = NSSize(width: targetDimension, height: targetDimension)
        return resizedImage(image, to: targetSize)
    }

    private func resizedImage(_ image: NSImage, to size: NSSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return image }
        guard image.size.width > size.width || image.size.height > size.height else {
            return image
        }

        let resized = NSImage(size: size)
        resized.lockFocus()
        defer { resized.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        resized.isTemplate = image.isTemplate
        return resized
    }

    private func cacheCost(for image: NSImage) -> Int {
        let width = max(Int(image.size.width.rounded(.up)), 1)
        let height = max(Int(image.size.height.rounded(.up)), 1)
        return width * height * 4
    }
}
