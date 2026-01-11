//
//  LaunchAtLoginManager.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import ServiceManagement

enum LaunchAtLoginManager {
    @available(macOS 13.0, *)
    private static var cachedStatus: SMAppService.Status?

    static var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            if let cachedStatus {
                return cachedStatus == .enabled
            }
            return refreshStatus()
        }
        return false
    }

    @discardableResult
    static func refreshStatus() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        let status = SMAppService.mainApp.status
        cachedStatus = status
        return status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        cachedStatus = enabled ? .enabled : .notRegistered
    }
}
