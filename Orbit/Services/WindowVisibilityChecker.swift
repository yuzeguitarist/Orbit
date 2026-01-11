//
//  WindowVisibilityChecker.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import CoreGraphics

enum WindowVisibilityChecker {
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

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.01 else { continue }

            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               bounds.width > 1,
               bounds.height > 1 {
                return true
            }

            return true
        }

        return false
    }
}
