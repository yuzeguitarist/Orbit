import Foundation

struct AppListPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedAppIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "orbit.excludedAppIDs") ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: "orbit.excludedAppIDs") }
    }

    var pinnedAppIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "orbit.pinnedAppIDs") ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: "orbit.pinnedAppIDs") }
    }

    var onlyAppsWithWindows: Bool {
        get { defaults.bool(forKey: "orbit.onlyAppsWithWindows") }
        nonmutating set { defaults.set(newValue, forKey: "orbit.onlyAppsWithWindows") }
    }
}

extension OrbitConfig {
    static var excludedAppIDs: Set<String> {
        get { AppListPreferences(defaults: defaults).excludedAppIDs }
        set { AppListPreferences(defaults: defaults).excludedAppIDs = newValue }
    }

    static var pinnedAppIDs: Set<String> {
        get { AppListPreferences(defaults: defaults).pinnedAppIDs }
        set { AppListPreferences(defaults: defaults).pinnedAppIDs = newValue }
    }

    static var onlyAppsWithWindows: Bool {
        get { AppListPreferences(defaults: defaults).onlyAppsWithWindows }
        set { AppListPreferences(defaults: defaults).onlyAppsWithWindows = newValue }
    }
}
