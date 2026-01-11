//
//  AppInfo.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import Foundation

/// 表示一个正在运行的应用程序信息
struct AppInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    let bundleURL: URL?
    let processIdentifier: pid_t

    /// 获取应用名称的首字母
    var firstLetter: Character? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let latinized = trimmedName.applyingTransform(.toLatin, reverse: false) ?? trimmedName
        let stripped = latinized.applyingTransform(.stripDiacritics, reverse: false) ?? latinized
        let letters = stripped.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard let firstLetter = letters.first else { return nil }
        return String(firstLetter).uppercased().first
    }

    /// 激活此应用（切换到前台）- 支持全屏模式
    func activate() -> Bool {
        // 方法1：使用 NSRunningApplication
        if let app = NSRunningApplication(processIdentifier: processIdentifier) {
            // 取消隐藏
            if app.isHidden {
                app.unhide()
            }

            let result: Bool
            if #available(macOS 14.0, *) {
                result = app.activate(options: [.activateAllWindows])
            } else {
                result = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }

            if result {
                if WindowVisibilityChecker.hasVisibleWindow(processIdentifier: processIdentifier) {
                    print("AppInfo: Activated \(name) via NSRunningApplication")
                    return true
                }

                // 无可见窗口时，尝试触发应用重新打开窗口
                if let url = bundleURL {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    config.hidesOthers = false

                    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                        if let error = error {
                            print("AppInfo: Failed to reopen \(self.name): \(error)")
                        } else {
                            print("AppInfo: Reopened \(self.name) via NSWorkspace")
                        }
                    }
                    return true
                }

                print("AppInfo: Activated \(name) via NSRunningApplication")
                return true
            }
        }

        // 方法2：使用 NSWorkspace 打开应用（适用于全屏等特殊情况）
        if let url = bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.hidesOthers = false

            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error = error {
                    print("AppInfo: Failed to open \(self.name): \(error)")
                } else {
                    print("AppInfo: Opened \(self.name) via NSWorkspace")
                }
            }
            return true
        }

        print("AppInfo: Failed to activate \(name)")
        return false
    }

    /// 终止此应用
    /// - Parameters:
    ///   - gracePeriod: 优雅退出等待时间（秒），超时后强制退出
    ///   - completion: 完成回调，参数为是否成功终止
    func terminate(gracePeriod: TimeInterval = OrbitConfig.terminateGracePeriod, completion: @escaping (Bool) -> Void) {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier) else {
            print("AppInfo: Cannot find running app \(name)")
            completion(false)
            return
        }

        // 尝试优雅退出
        let terminated = app.terminate()
        print("AppInfo: Attempting graceful termination of \(name), result: \(terminated)")

        if terminated {
            // 监控应用是否真正退出
            DispatchQueue.main.asyncAfter(deadline: .now() + gracePeriod) {
                if app.isTerminated {
                    print("AppInfo: \(self.name) terminated gracefully")
                    completion(true)
                } else {
                    // 超时，强制退出
                    print("AppInfo: \(self.name) did not respond, force terminating...")
                    let forceResult = app.forceTerminate()
                    print("AppInfo: Force terminate result: \(forceResult)")
                    completion(forceResult)
                }
            }
        } else {
            // 直接尝试强制退出
            print("AppInfo: Graceful termination failed, attempting force terminate...")
            let forceResult = app.forceTerminate()
            print("AppInfo: Force terminate result: \(forceResult)")
            completion(forceResult)
        }
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }
}
