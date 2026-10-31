//
//  WindowVisibilityChecker.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import CoreGraphics

enum WindowVisibilityChecker {
    /// 包括其他空间、隐藏和最小化的窗口；不读取窗口标题或内容。
    static func windowOwnerProcessIdentifiers() -> Set<pid_t> {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return windowOwnerProcessIdentifiers(in: infoList)
    }

    static func windowOwnerProcessIdentifiers(in infoList: [[String: Any]]) -> Set<pid_t> {
        Set(infoList.compactMap { info in
            guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int,
                  isApplicationWindow(info) else { return nil }
            return pid_t(ownerPid)
        })
    }

    static func hasVisibleWindow(processIdentifier: pid_t) -> Bool {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for info in infoList {
            guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPid == Int(processIdentifier) else {
                continue
            }

            guard isApplicationWindow(info) else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.01 else { continue }
            return true
        }

        return false
    }

    private static func isApplicationWindow(_ info: [String: Any]) -> Bool {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return false }
        return bounds.width > 1 && bounds.height > 1
    }
}
