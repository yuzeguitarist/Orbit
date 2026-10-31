//
//  AppListService.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import Foundation

struct AppUsageHistory {
    private(set) var recentAppIDs: [String] = []

    mutating func recordActivation(appID: String) {
        recentAppIDs.removeAll { $0 == appID }
        recentAppIDs.insert(appID, at: 0)
    }

    mutating func retainRunningApps(_ runningAppIDs: Set<String>) {
        recentAppIDs.removeAll { !runningAppIDs.contains($0) }
    }

    func orderedApps(_ apps: [AppInfo]) -> [AppInfo] {
        let ranks = Dictionary(uniqueKeysWithValues: recentAppIDs.enumerated().map { ($0.element, $0.offset) })
        return apps.enumerated().sorted { lhs, rhs in
            let leftRank = ranks[lhs.element.id] ?? Int.max
            let rightRank = ranks[rhs.element.id] ?? Int.max
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)
    }
}

struct AppListCandidate {
    let app: AppInfo
    let isRegular: Bool
}

enum AppListPolicy {
    static func apps(
        from candidates: [AppListCandidate],
        excludingProcessIdentifier: pid_t?,
        ownAppID: String?,
        ownProcessIdentifier: pid_t,
        excludedAppIDs: Set<String>,
        pinnedAppIDs: Set<String>,
        windowProcessIdentifiers: Set<pid_t>?,
        history: AppUsageHistory
    ) -> [AppInfo] {
        let filtered = candidates.compactMap { candidate -> AppInfo? in
            let app = candidate.app
            guard app.processIdentifier != ownProcessIdentifier,
                  app.id != ownAppID,
                  app.processIdentifier != excludingProcessIdentifier,
                  !excludedAppIDs.contains(app.id) else { return nil }
            let isPinned = pinnedAppIDs.contains(app.id)
            guard candidate.isRegular || isPinned else { return nil }
            if let windowProcessIdentifiers, !isPinned,
               !windowProcessIdentifiers.contains(app.processIdentifier) {
                return nil
            }
            return app
        }
        let ordered = history.orderedApps(filtered)
        let limit = OrbitConfig.maxVisibleCards
        guard ordered.count > limit, !pinnedAppIDs.isEmpty else { return ordered }

        // 保留最近应用作为快捷切换目标，固定项占用其余可见位置。
        var admittedIndices: Set<Int> = [0]
        for index in ordered.indices.dropFirst() where admittedIndices.count < limit {
            if pinnedAppIDs.contains(ordered[index].id) {
                admittedIndices.insert(index)
            }
        }
        for index in ordered.indices where admittedIndices.count < limit {
            admittedIndices.insert(index)
        }
        let visible = ordered.enumerated().filter { admittedIndices.contains($0.offset) }.map(\.element)
        let remaining = ordered.enumerated().filter { !admittedIndices.contains($0.offset) }.map(\.element)
        return visible + remaining
    }
}

/// 获取和管理正在运行的应用列表
final class AppListService {
    static let shared = AppListService()
    private let iconCache = NSCache<NSString, NSImage>()
    private let fallbackIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    private var usageHistory = AppUsageHistory()
    private var activationObserver: Any?

    private init() {
        iconCache.countLimit = 64
        iconCache.totalCostLimit = 24 * 1024 * 1024
    }

    static func appIdentifier(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier)
    }

    /// 从启动时开始观察，确保第一次呼出前的应用切换也被记录。
    func startTracking() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                self?.recordActivation(of: app)
            }
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            recordActivation(of: app)
        }
    }

    private func recordActivation(of app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        usageHistory.recordActivation(appID: Self.appIdentifier(for: app))
    }

    /// 获取当前正在运行的普通应用列表
    /// - Parameter excludingProcessIdentifier: 需要排除的进程 ID（如当前前台应用）
    func getRunningApps(excludingProcessIdentifier: pid_t? = nil) -> [AppInfo] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let activePid = excludingProcessIdentifier ?? workspace.frontmostApplication?.processIdentifier
        usageHistory.retainRunningApps(Set(runningApps.map(Self.appIdentifier)))
        if let activeApp = runningApps.first(where: { $0.processIdentifier == activePid }) {
            recordActivation(of: activeApp)
        }
        let candidates = runningApps.map { app in
            AppListCandidate(
                app: AppInfo(
                    id: Self.appIdentifier(for: app),
                    name: app.localizedName ?? "Unknown",
                    bundleURL: app.bundleURL,
                    processIdentifier: app.processIdentifier
                ),
                isRegular: app.activationPolicy == .regular
            )
        }
        return AppListPolicy.apps(
            from: candidates,
            excludingProcessIdentifier: activePid,
            ownAppID: Bundle.main.bundleIdentifier,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            excludedAppIDs: OrbitConfig.excludedAppIDs,
            pinnedAppIDs: OrbitConfig.pinnedAppIDs,
            windowProcessIdentifiers: OrbitConfig.onlyAppsWithWindows ? WindowVisibilityChecker.windowOwnerProcessIdentifiers() : nil,
            history: usageHistory
        )
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
