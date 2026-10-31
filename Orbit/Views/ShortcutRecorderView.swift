import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: TriggerShortcut?
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var invalidShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("settings.trigger.shortcut")
                Spacer()
                Text(shortcut?.displayString ?? NSLocalizedString("settings.trigger.shortcut.none", comment: ""))
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("settings.trigger.shortcut.value")
                Button(isRecording ? "settings.trigger.shortcut.recording" : "settings.trigger.shortcut.record") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .accessibilityIdentifier("settings.trigger.shortcut.record")
                if shortcut != nil {
                    Button("settings.trigger.shortcut.clear") {
                        stopRecording()
                        shortcut = nil
                    }
                    .accessibilityIdentifier("settings.trigger.shortcut.clear")
                }
            }
            Text(invalidShortcut ? "settings.trigger.shortcut.needs_modifier" : "settings.trigger.shortcut.hint")
                .font(.caption)
                .foregroundColor(invalidShortcut ? .red : .secondary)
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
    }

    private func startRecording() {
        invalidShortcut = false
        isRecording = true
        HotKeyService.shared.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat else { return nil }
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let candidate = TriggerShortcut(event: event)
            guard candidate.isValidCustomShortcut else {
                invalidShortcut = true
                return nil
            }
            shortcut = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        HotKeyService.shared.isRecordingShortcut = false
    }
}
