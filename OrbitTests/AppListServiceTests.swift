import AppKit
import Testing
@testable import Orbit

@MainActor
struct AppListServiceTests {
    private func candidate(_ id: String, _ pid: pid_t, regular: Bool = true) -> AppListCandidate {
        AppListCandidate(
            app: AppInfo(id: id, name: id, bundleURL: nil, processIdentifier: pid),
            isRegular: regular
        )
    }

    private func filtered(
        _ candidates: [AppListCandidate],
        excluding currentPID: pid_t? = nil,
        excluded: Set<String> = [],
        pinned: Set<String> = [],
        windows: Set<pid_t>? = nil,
        history: AppUsageHistory = AppUsageHistory()
    ) -> [AppInfo] {
        AppListPolicy.apps(
            from: candidates,
            excludingProcessIdentifier: currentPID,
            ownAppID: "orbit",
            ownProcessIdentifier: 999,
            excludedAppIDs: excluded,
            pinnedAppIDs: pinned,
            windowProcessIdentifiers: windows,
            history: history
        )
    }

    @Test func recentAppsAlternateWithoutPredictionChangingTheTarget() {
        let candidates = [candidate("old", 1), candidate("A", 2), candidate("B", 3)]
        var history = AppUsageHistory()
        history.recordActivation(appID: "old")
        history.recordActivation(appID: "A")
        history.recordActivation(appID: "B")
        #expect(filtered(candidates, excluding: 3, history: history).first?.id == "A")

        history.recordActivation(appID: "A")
        #expect(filtered(candidates, excluding: 2, history: history).first?.id == "B")
        history.recordActivation(appID: "B")
        #expect(filtered(candidates, excluding: 3, history: history).first?.id == "A")
    }

    @Test func repeatedActivationDoesNotDuplicateAppsAndUnknownAppsStayStable() {
        var history = AppUsageHistory()
        history.recordActivation(appID: "B")
        history.recordActivation(appID: "A")
        history.recordActivation(appID: "B")
        #expect(history.recentAppIDs == ["B", "A"])
        let apps = [candidate("unknown1", 1), candidate("A", 2), candidate("unknown2", 3), candidate("B", 4)]
        #expect(filtered(apps, history: history).map(\.id) == ["B", "A", "unknown1", "unknown2"])
    }

    @Test func closedAppsArePrunedAndRelaunchCanBecomeMostRecent() {
        var history = AppUsageHistory()
        history.recordActivation(appID: "A")
        history.recordActivation(appID: "B")
        history.retainRunningApps(["A"])
        #expect(history.recentAppIDs == ["A"])
        history.recordActivation(appID: "B")
        #expect(history.recentAppIDs == ["B", "A"])
    }

    @Test func presentationSnapshotDoesNotMoveAfterAnotherActivation() {
        var history = AppUsageHistory()
        history.recordActivation(appID: "A")
        let apps = [candidate("B", 1), candidate("A", 2)]
        let snapshot = filtered(apps, history: history)
        history.recordActivation(appID: "B")
        #expect(snapshot.map(\.id) == ["A", "B"])
        #expect(filtered(apps, history: history).map(\.id) == ["B", "A"])
    }

    @Test func selfCurrentAndExcludedAppsCannotBeForcedBackByPinning() {
        let apps = [candidate("orbit", 10), candidate("renamedOrbit", 999), candidate("current", 20), candidate("excluded", 30), candidate("keep", 40)]
        let pinned: Set<String> = ["orbit", "renamedOrbit", "current", "excluded", "keep"]
        #expect(filtered(apps, excluding: 20, excluded: ["excluded"], pinned: pinned, windows: []).map(\.id) == ["keep"])
    }

    @Test func explicitPinOverridesWindowAndRegularAppFiltersWithoutAddingStoppedApps() {
        let apps = [candidate("visible", 1), candidate("noWindow", 2), candidate("accessory", 3, regular: false), candidate("daemon", 4, regular: false)]
        #expect(filtered(apps, windows: [1]).map(\.id) == ["visible"])
        #expect(filtered(apps, pinned: ["noWindow", "accessory", "stopped"], windows: [1]).map(\.id) == ["visible", "noWindow", "accessory"])
    }

    @Test func pinningKeepsMostRecentAppFirstAndFiltersCompose() {
        let apps = [candidate("pinned", 1), candidate("recent", 2), candidate("excluded", 3), candidate("current", 4)]
        var history = AppUsageHistory()
        history.recordActivation(appID: "pinned")
        history.recordActivation(appID: "recent")
        history.recordActivation(appID: "current")
        let result = filtered(apps, excluding: 4, excluded: ["excluded"], pinned: ["pinned"], windows: [2, 3, 4], history: history)
        #expect(result.map(\.id) == ["recent", "pinned"])
    }

    @Test func disabledWindowFilterRetainsNormalAppsWithoutWindows() {
        let apps = [candidate("window", 1), candidate("noWindow", 2), candidate("accessory", 3, regular: false)]
        #expect(filtered(apps).map(\.id) == ["window", "noWindow"])
    }

    @Test func aStalePinAppearsInsideTheVisibleRingWithoutReplacingTheMostRecentTarget() {
        let apps = (0 ..< 17).map { candidate("app\($0)", pid_t($0 + 1)) }
        var history = AppUsageHistory()
        for index in (0 ..< 17).reversed() {
            history.recordActivation(appID: "app\(index)")
        }
        let result = filtered(apps, pinned: ["app16"], history: history)
        #expect(result.first?.id == "app0")
        #expect(result.prefix(12).map(\.id) == (0 ..< 11).map { "app\($0)" } + ["app16"])
        #expect(result.dropFirst(12).map(\.id) == (11 ..< 16).map { "app\($0)" })
        #expect(result.count == apps.count)
    }

    @Test func morePinsThanSlotsUseTheirRecentOrderAndDoNotDuplicateEntries() {
        let apps = (0 ..< 17).map { candidate("app\($0)", pid_t($0 + 1)) }
        var history = AppUsageHistory()
        for index in (0 ..< 17).reversed() {
            history.recordActivation(appID: "app\(index)")
        }
        let result = filtered(apps, pinned: Set((1 ..< 17).map { "app\($0)" }), history: history)
        #expect(result.prefix(12).map(\.id) == (0 ..< 12).map { "app\($0)" })
        #expect(Set(result.map(\.id)).count == apps.count)
        #expect(result.count == apps.count)
    }

    @Test func preferencesPersistInTheirOwnDefaultsDomain() throws {
        let suite = "OrbitTests.AppListPreferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppListPreferences(defaults: defaults)
        #expect(preferences.excludedAppIDs.isEmpty)
        #expect(preferences.pinnedAppIDs.isEmpty)
        #expect(!preferences.onlyAppsWithWindows)
        preferences.excludedAppIDs = ["hidden", "finder"]
        preferences.pinnedAppIDs = ["pinned"]
        preferences.onlyAppsWithWindows = true

        let reloaded = AppListPreferences(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(reloaded.excludedAppIDs == ["hidden", "finder"])
        #expect(reloaded.pinnedAppIDs == ["pinned"])
        #expect(reloaded.onlyAppsWithWindows)
        reloaded.excludedAppIDs = []
        reloaded.onlyAppsWithWindows = false
        #expect(preferences.excludedAppIDs.isEmpty)
        #expect(!preferences.onlyAppsWithWindows)
    }

    @Test func windowFilterIncludesOffscreenWindowsButRejectsOverlaysAndEmptyBounds() {
        func window(_ pid: Int, layer: Int = 0, bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: pid,
                kCGWindowLayer as String: layer,
                kCGWindowBounds as String: bounds.dictionaryRepresentation,
                kCGWindowAlpha as String: 0,
                kCGWindowIsOnscreen as String: false
            ]
        }
        let windows = [window(1), window(1), window(2, layer: 8), window(3, bounds: .zero), [kCGWindowOwnerPID as String: 4]]
        #expect(WindowVisibilityChecker.windowOwnerProcessIdentifiers(in: windows) == [1])
    }
}
