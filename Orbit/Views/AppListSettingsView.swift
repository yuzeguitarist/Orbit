import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppListSettingsView: View {
    @State private var excludedAppIDs = OrbitConfig.excludedAppIDs
    @State private var pinnedAppIDs = OrbitConfig.pinnedAppIDs
    @State private var onlyAppsWithWindows = OrbitConfig.onlyAppsWithWindows

    var body: some View {
        Section("settings.section.apps") {
            Toggle("settings.apps.only_windows", isOn: $onlyAppsWithWindows)
                .accessibilityIdentifier("settings.apps.only_windows")
                .onChange(of: onlyAppsWithWindows) { _, newValue in
                    OrbitConfig.onlyAppsWithWindows = newValue
                }
            Text("settings.apps.only_windows_hint")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("settings.apps.exclude") { chooseApplications(exclude: true) }
                    .accessibilityIdentifier("settings.apps.exclude")
                Button("settings.apps.pin") { chooseApplications(exclude: false) }
                    .accessibilityIdentifier("settings.apps.pin")
            }
            if excludedAppIDs.isEmpty && pinnedAppIDs.isEmpty {
                Text("settings.apps.empty")
                    .foregroundColor(.secondary)
            }
            ruleRows(ids: excludedAppIDs, title: "settings.apps.excluded", exclude: true)
            ruleRows(ids: pinnedAppIDs, title: "settings.apps.pinned", exclude: false)
            Text("settings.apps.pin_hint")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            excludedAppIDs = OrbitConfig.excludedAppIDs
            pinnedAppIDs = OrbitConfig.pinnedAppIDs
            onlyAppsWithWindows = OrbitConfig.onlyAppsWithWindows
        }
    }

    private func ruleRows(ids: Set<String>, title: LocalizedStringKey, exclude: Bool) -> some View {
        ForEach(ids.sorted(), id: \.self) { id in
            HStack {
                VStack(alignment: .leading) {
                    Text(applicationName(for: id))
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if exclude {
                        excludedAppIDs.remove(id)
                        OrbitConfig.excludedAppIDs = excludedAppIDs
                    } else {
                        pinnedAppIDs.remove(id)
                        OrbitConfig.pinnedAppIDs = pinnedAppIDs
                    }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(Text("settings.apps.remove"))
                .accessibilityLabel(Text("settings.apps.remove"))
                .accessibilityIdentifier("settings.apps.remove.\(id)")
            }
        }
    }

    private func chooseApplications(exclude: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = NSLocalizedString("settings.apps.choose", comment: "")
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                let id = Bundle(url: url)?.bundleIdentifier ?? url.path
                if exclude {
                    excludedAppIDs.insert(id)
                    pinnedAppIDs.remove(id)
                } else {
                    pinnedAppIDs.insert(id)
                    excludedAppIDs.remove(id)
                }
            }
            OrbitConfig.excludedAppIDs = excludedAppIDs
            OrbitConfig.pinnedAppIDs = pinnedAppIDs
        }
    }

    private func applicationName(for id: String) -> String {
        let url = id.hasPrefix("/") ? URL(fileURLWithPath: id) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        guard let url else { return id }
        return FileManager.default.displayName(atPath: url.path)
    }
}
