//
//  ClipboardShareService.swift
//  Orbit
//
//  Created by Yuze Pan on 1/12/26.
//

import AppKit
import Foundation

final class ClipboardShareService: NSObject, NSSharingServiceDelegate {
    static let shared = ClipboardShareService()

    private var temporaryShareURLs: [URL] = []
    private var activeService: NSSharingService?

    private override init() {
        super.init()
    }

    func share(payload: OrbitClipboardPayload, completion: @escaping (Bool) -> Void) {
        temporaryShareURLs.removeAll()
        let items = shareItems(from: payload)
        guard !items.isEmpty else {
            completion(false)
            return
        }

        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            print("ClipboardShareService: AirDrop service not available")
            completion(false)
            return
        }

        if service.canPerform(withItems: items) {
            DispatchQueue.main.async {
                self.activeService = service
                service.delegate = self
                service.perform(withItems: items)
                completion(true)
            }
        } else {
            print("ClipboardShareService: Cannot perform AirDrop with payload")
            cleanupTemporaryFiles()
            completion(false)
        }
    }

    private func shareItems(from payload: OrbitClipboardPayload) -> [Any] {
        switch payload.itemTypeValue {
        case .text, .richText, .color:
            if let text = payload.text, !text.isEmpty {
                if let url = makeTemporaryTextFile(text: text, baseName: "Orbit-Clipboard", fileExtension: "txt") {
                    return [url]
                }
            }
            return []

        case .code:
            if let text = payload.text, !text.isEmpty {
                let fileExtension = codeFileExtension(pasteboardType: payload.pasteboardType, text: text)
                if let url = makeTemporaryTextFile(text: text, baseName: "Orbit-Code", fileExtension: fileExtension) {
                    return [url]
                }
            }
            return []

        case .url:
            guard let urlString = payload.urlString, !urlString.isEmpty else { return [] }
            if let url = URL(string: urlString) {
                return [url]
            }
            return [urlString]

        case .file:
            guard let filePaths = payload.filePaths else { return [] }
            return filePaths
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }

        case .image:
            if let filePaths = payload.filePaths, !filePaths.isEmpty {
                return filePaths
                    .map { URL(fileURLWithPath: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            if let data = payload.imageData, let image = NSImage(data: data) {
                return [image]
            }
            return []
        }
    }

    private func codeFileExtension(pasteboardType: String, text: String) -> String {
        let type = pasteboardType.lowercased()
        if type.contains("swift") { return "swift" }
        if type.contains("python") { return "py" }
        if type.contains("plist") { return "plist" }
        if type.contains("shell") || type.contains("bash") || type.contains("zsh") { return "sh" }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shebang = normalizedText.components(separatedBy: .newlines).first?.lowercased(),
           shebang.hasPrefix("#!")
        {
            if shebang.contains("python") { return "py" }
            if shebang.contains("bash") || shebang.contains("zsh") || shebang.contains("sh") { return "sh" }
        }

        let lowercaseText = normalizedText.lowercased()
        if lowercaseText.hasPrefix("<?xml"), lowercaseText.contains("<plist") { return "plist" }
        if lowercaseText.contains("import swiftui") || lowercaseText.contains("import appkit") || lowercaseText.contains("import foundation") {
            return "swift"
        }

        return "code"
    }

    private func makeTemporaryTextFile(text: String, baseName: String, fileExtension: String) -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        let url = tempDir.appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            temporaryShareURLs.append(url)
            return url
        } catch {
            print("ClipboardShareService: Failed to write temp file: \(error)")
            return nil
        }
    }

    private func cleanupTemporaryFiles() {
        for url in temporaryShareURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryShareURLs.removeAll()
        activeService = nil
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        cleanupTemporaryFiles()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        print("ClipboardShareService: AirDrop failed: \(error)")
        cleanupTemporaryFiles()
    }
}
