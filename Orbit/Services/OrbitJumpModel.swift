//
//  OrbitJumpModel.swift
//  Orbit
//
//  Created by Codex on 2025/02/10.
//

import Foundation

actor OrbitJumpModel {
    static let shared = OrbitJumpModel()

    private struct TransitionStats: Codable {
        var count: Double
        var lastUpdated: TimeInterval
    }

    private struct PersistedState: Codable {
        var version: Int
        var transitions: [String: [String: TransitionStats]]
    }

    private let maxStorageBytes = 20 * 1024 * 1024
    private let countHalfLife: TimeInterval = 7 * 24 * 60 * 60
    private let saveDebounce: TimeInterval = 1.0
    private let storageURL: URL

    private var transitions: [String: [String: TransitionStats]] = [:]
    private var isLoaded = false
    private var saveTask: Task<Void, Never>?

    private init() {
        storageURL = Self.makeStorageURL()
    }

    func recordTransition(from: String, to: String) async {
        guard from != to else { return }
        await loadIfNeeded()

        let now = Date().timeIntervalSince1970
        var toMap = transitions[from] ?? [:]
        let existing = toMap[to] ?? TransitionStats(count: 0, lastUpdated: now)
        let decayedCount = decayed(existing, now: now)
        toMap[to] = TransitionStats(count: decayedCount + 1, lastUpdated: now)
        transitions[from] = toMap

        scheduleSave()
    }

    func rankedAppIds(contextAppId: String, candidates: [String]) async -> [String] {
        await loadIfNeeded()
        guard let contextMap = transitions[contextAppId], !contextMap.isEmpty else {
            return candidates
        }

        let now = Date().timeIntervalSince1970
        var scored: [(id: String, score: Double, index: Int)] = []
        scored.reserveCapacity(candidates.count)

        for (index, id) in candidates.enumerated() {
            if let stats = contextMap[id] {
                let score = decayed(stats, now: now)
                scored.append((id, score, index))
            } else {
                scored.append((id, 0, index))
            }
        }

        guard scored.contains(where: { $0.score > 0 }) else {
            return candidates
        }

        scored.sort {
            if $0.score == $1.score {
                return $0.index < $1.index
            }
            return $0.score > $1.score
        }

        return scored.map { $0.id }
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true

        do {
            let data = try Data(contentsOf: storageURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            transitions = state.transitions
            if data.count > maxStorageBytes {
                await pruneToFit()
                scheduleSave()
            }
        } catch {
            transitions = [:]
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.saveDebounce * 1_000_000_000))
            await self.saveNow()
        }
    }

    private func saveNow() async {
        let state = PersistedState(version: 1, transitions: transitions)
        guard var data = try? JSONEncoder().encode(state) else { return }

        if data.count > maxStorageBytes {
            await pruneToFit()
            let prunedState = PersistedState(version: 1, transitions: transitions)
            guard let prunedData = try? JSONEncoder().encode(prunedState) else { return }
            data = prunedData
        }

        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            return
        }
    }

    private func pruneToFit() async {
        var attempts = 0
        while attempts < 6 {
            let state = PersistedState(version: 1, transitions: transitions)
            guard let data = try? JSONEncoder().encode(state) else { return }
            if data.count <= maxStorageBytes {
                return
            }
            if !removeOldestTransitions(fraction: 0.1) {
                return
            }
            attempts += 1
        }
    }

    private func removeOldestTransitions(fraction: Double) -> Bool {
        var edges: [(from: String, to: String, lastUpdated: TimeInterval)] = []

        for (from, map) in transitions {
            for (to, stats) in map {
                edges.append((from, to, stats.lastUpdated))
            }
        }

        guard !edges.isEmpty else { return false }
        edges.sort { $0.lastUpdated < $1.lastUpdated }

        let removeCount = max(Int(Double(edges.count) * fraction), 50)
        let actualCount = min(removeCount, edges.count)
        if actualCount == 0 { return false }

        for index in 0..<actualCount {
            let edge = edges[index]
            transitions[edge.from]?[edge.to] = nil
            if transitions[edge.from]?.isEmpty == true {
                transitions[edge.from] = nil
            }
        }

        return true
    }

    private func decayed(_ stats: TransitionStats, now: TimeInterval) -> Double {
        let elapsed = max(0, now - stats.lastUpdated)
        if elapsed == 0 {
            return stats.count
        }
        let decayFactor = pow(0.5, elapsed / countHalfLife)
        return stats.count * decayFactor
    }

    private static func makeStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Orbit", isDirectory: true)
            .appendingPathComponent("orbit_jump_model.json")
    }
}
