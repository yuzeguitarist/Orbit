//
//  FileDragDropService.swift
//  Orbit
//
//  Created by Claude on 1/8/26.
//

import AppKit
import Foundation

/// 文件拖放处理服务
/// 提供 AirDrop 分享和废纸篓移动功能
@MainActor
final class FileDragDropService {
    static let shared = FileDragDropService()

    private init() {}

    // MARK: - AirDrop

    /// 通过 AirDrop 分享文件
    /// - Parameters:
    ///   - urls: 要分享的文件 URLs
    ///   - completion: 完成回调，参数为是否成功
    func shareViaAirDrop(urls: [URL], completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard !urls.isEmpty else {
            completion(false)
            return
        }

        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            print("FileDragDropService: AirDrop service not available")
            completion(false)
            return
        }

        // 检查是否可以执行分享
        if service.canPerform(withItems: urls) {
            // 在主线程执行分享
            DispatchQueue.main.async {
                service.perform(withItems: urls)
                print("FileDragDropService: AirDrop initiated for \(urls.count) file(s)")
                completion(true)
            }
        } else {
            print("FileDragDropService: Cannot perform AirDrop with provided items")
            completion(false)
        }
    }

    // MARK: - Trash

    /// 移动文件到废纸篓
    /// - Parameters:
    ///   - urls: 要移动的文件 URLs
    ///   - completion: 完成回调，参数为是否全部成功和可能的错误
    func moveToTrash(urls: [URL], completion: @escaping @MainActor @Sendable (Bool, Error?) -> Void) {
        guard !urls.isEmpty else {
            completion(true, nil)
            return
        }

        let fileManager = FileManager.default
        var allSuccess = true
        var lastError: Error?

        for url in urls {
            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                print("FileDragDropService: Moved to trash: \(url.lastPathComponent)")
            } catch {
                allSuccess = false
                lastError = error
                print("FileDragDropService: Failed to trash \(url.lastPathComponent): \(error)")
            }
        }

        completion(allSuccess, lastError)
    }

    /// 使用 NSWorkspace 移动文件到废纸篓（备选方案）
    /// - Parameters:
    ///   - urls: 要移动的文件 URLs
    ///   - completion: 完成回调
    func moveToTrashViaWorkspace(urls: [URL], completion: @escaping @MainActor @Sendable (Bool, Error?) -> Void) {
        guard !urls.isEmpty else {
            completion(true, nil)
            return
        }

        NSWorkspace.shared.recycle(urls) { trashedURLs, error in
            if let error = error {
                print("FileDragDropService: Workspace recycle failed: \(error)")
                Task { @MainActor in
                    completion(false, error)
                }
            } else {
                print("FileDragDropService: Recycled \(trashedURLs.count) file(s) via Workspace")
                Task { @MainActor in
                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - Helpers

    /// 从 NSDraggingInfo 中提取文件 URLs
    /// - Parameter info: 拖拽信息
    /// - Returns: 文件 URL 数组，如果没有文件则返回 nil
    func extractFileURLs(from info: NSDraggingInfo) -> [URL]? {
        let pasteboard = info.draggingPasteboard

        // 尝试读取文件 URLs
        guard let items = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }

        // 过滤掉非文件 URL
        let fileURLs = items.filter { $0.isFileURL }
        return fileURLs.isEmpty ? nil : fileURLs
    }

    /// 检查 URL 是否是有效的文件
    /// - Parameter url: 要检查的 URL
    /// - Returns: 是否是有效文件
    func isValidFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        return exists
    }
}
