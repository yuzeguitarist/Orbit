//
//  ClipboardRingViewModel.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class ClipboardRingViewModel: ObservableObject {
    static let maxVisibleCards = 9

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var items: [OrbitClipboardSummary] = []
    @Published var selectedIndex: Int = -1
    @Published var isExpanding = false
    @Published var isFullyExpanded = false
    @Published var cardAnimationProgress: [Double] = []
    @Published private(set) var cardDragStates: [String: CardDragState] = [:]
    @Published private(set) var cardDissolveProgress: [String: Double] = [:]
    @Published var airDropIndicatorState: AirDropIndicatorState = .hidden
    @Published var loadState: LoadState = .idle

    var onLoadFailure: (() -> Void)?

    private var isPresentationActive = false
    private var pendingStartAnimation = false
    private var loadRequestId = UUID()
    private var animationSequenceId = UUID()
    private var dissolveSequenceIds: [String: UUID] = [:]
    private var dropTransitionSequenceId = UUID()

    private var airDropToBlackHoleTimer: Timer?
    private var activeDropId: String?

    private let bridgeClient = OrbitBridgeClient.shared
    private let decoder = JSONDecoder()

    private var visibleCount: Int {
        min(items.count, Self.maxVisibleCards)
    }

    var selectedItem: OrbitClipboardSummary? {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    func loadItemsForRing() {
        loadRequestId = UUID()
        loadState = .loading
        pendingStartAnimation = false
        fetchItems(attempt: 0, requestId: loadRequestId)
    }

    func resetState() {
        loadRequestId = UUID()
        items = []
        selectedIndex = -1
        loadState = .idle
        isPresentationActive = false
        pendingStartAnimation = false
        resetAnimationState()
    }

    func activatePresentation() {
        isPresentationActive = true
        if pendingStartAnimation {
            pendingStartAnimation = false
            startExpandAnimation()
        }
    }

    func deactivatePresentation() {
        isPresentationActive = false
    }

    func startExpandAnimation() {
        let animationSequenceId = UUID()
        self.animationSequenceId = animationSequenceId
        isExpanding = true
        isFullyExpanded = false
        let count = visibleCount
        let speed = OrbitConfig.ringAnimationSpeed
        let clampedSpeed = max(speed, 0.1)
        let response = 0.35 / clampedSpeed
        let delayStep = OrbitConfig.cardStaggerDelay / clampedSpeed
        cardAnimationProgress = Array(repeating: 0, count: count)

        for i in 0 ..< count {
            let delay = Double(i) * delayStep
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.animationSequenceId == animationSequenceId else { return }
                guard i < self.cardAnimationProgress.count else { return }
                withAnimation(.spring(response: response, dampingFraction: 0.75)) {
                    self.cardAnimationProgress[i] = 1.0
                }
            }
        }

        let totalDuration = 0.4 / clampedSpeed + Double(count) * delayStep
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self else { return }
            guard self.animationSequenceId == animationSequenceId else { return }
            self.isExpanding = false
            self.isFullyExpanded = true
        }
    }

    private func fetchItems(attempt: Int, requestId: UUID) {
        bridgeClient.fetchRecentItems(limit: Self.maxVisibleCards) { [weak self] result in
            guard let self else { return }
            let decodedResult: Result<[OrbitClipboardSummary], Error>
            let failurePrefix: String?

            switch result {
            case .success(let data):
                do {
                    decodedResult = .success(try JSONDecoder().decode([OrbitClipboardSummary].self, from: data))
                    failurePrefix = nil
                } catch {
                    decodedResult = .failure(error)
                    failurePrefix = "ClipboardRingViewModel: Failed to decode items"
                }
            case .failure(let error):
                decodedResult = .failure(error)
                failurePrefix = "ClipboardRingViewModel: Failed to fetch items"
            }

            Task { @MainActor in
                guard self.loadRequestId == requestId else { return }

                switch decodedResult {
                case .success(let decodedItems):
                    self.items = decodedItems
                case .failure(let error):
                    if let failurePrefix {
                        print("\(failurePrefix): \(error)")
                    }
                    self.items = []
                    if attempt == 0 {
                        self.fetchItems(attempt: 1, requestId: requestId)
                        return
                    }
                    self.loadState = .failed(error.localizedDescription)
                    self.onLoadFailure?()
                    return
                }

                if self.items.isEmpty {
                    self.selectedIndex = -1
                    self.loadState = .empty
                    self.resetAnimationState()
                    self.pendingStartAnimation = false
                    self.onLoadFailure?()
                    return
                }

                self.selectedIndex = 0
                self.loadState = .loaded
                self.resetAnimationState()
                if self.isPresentationActive {
                    self.startExpandAnimation()
                } else {
                    self.pendingStartAnimation = true
                }
            }
        }
    }

    func startCollapseAnimation(speed: Double = 1.0, completion: @escaping () -> Void) {
        let animationSequenceId = UUID()
        self.animationSequenceId = animationSequenceId
        isFullyExpanded = false
        let count = visibleCount
        let clampedSpeed = max(speed * OrbitConfig.ringAnimationSpeed, 0.1)
        let response = 0.3 / clampedSpeed
        let delayStep = 0.02 / clampedSpeed

        for i in (0 ..< count).reversed() {
            let delay = Double(count - 1 - i) * delayStep
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.animationSequenceId == animationSequenceId else { return }
                guard i < self.cardAnimationProgress.count else { return }
                withAnimation(.spring(response: response, dampingFraction: 0.85)) {
                    self.cardAnimationProgress[i] = 0
                }
            }
        }

        let totalDuration = 0.35 / clampedSpeed + Double(count) * delayStep
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self else { return }
            guard self.animationSequenceId == animationSequenceId else { return }
            completion()
        }
    }

    enum KeyPressResult {
        case unhandled
        case handled
    }

    func handleKeyPress(
        _ keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> KeyPressResult {
        if keyCode == 48 { // Tab
            if modifierFlags.contains(.shift) {
                selectPrevious()
            } else {
                selectNext()
            }
            return .handled
        }

        switch keyCode {
        case 123, 126: // Left / Up
            selectPrevious()
            return .handled
        case 124, 125: // Right / Down
            selectNext()
            return .handled
        default:
            break
        }

        let primaryChar = characters?.first
        let fallbackChar = charactersIgnoringModifiers?.first
        let char: Character? = {
            if let fallback = fallbackChar, fallback.wholeNumberValue != nil {
                return fallback
            }
            if let primary = primaryChar, primary.wholeNumberValue != nil {
                return primary
            }
            return fallbackChar ?? primaryChar
        }()
        guard let char else { return .unhandled }

        if let number = char.wholeNumberValue, number >= 1 && number <= 9 {
            selectByNumber(number)
            return .handled
        }

        return .unhandled
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        if selectedIndex < 0 {
            selectedIndex = 0
            return
        }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        if selectedIndex < 0 {
            selectedIndex = items.count - 1
            return
        }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1
        guard index >= 0 && index < min(Self.maxVisibleCards, items.count) else { return }
        selectedIndex = index
    }

    func selectByIndex(_ index: Int) {
        guard index >= 0 && index < items.count else { return }
        selectedIndex = index
    }

    func copySelectedItem(completion: @escaping (Bool) -> Void) {
        guard let item = selectedItem else {
            completion(false)
            return
        }

        bridgeClient.copyItem(item.uniqueId) { result in
            switch result {
            case .success(let success):
                completion(success)
            case .failure(let error):
                print("ClipboardRingViewModel: Copy failed: \(error)")
                completion(false)
            }
        }
    }

    func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        let itemId = item.uniqueId
        deleteItems([itemId])
        let currentOffset = cardDragStates[itemId]?.offset ?? .zero
        cardDragStates[itemId] = .dissolving(offset: currentOffset)
        startDissolveAnimation(for: itemId) { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                self.removeItem(withId: itemId)
            }
        }
    }

    // MARK: - Drag handling

    func getCardAnimationProgress(index: Int) -> Double {
        index < cardAnimationProgress.count ? cardAnimationProgress[index] : 0
    }

    func getCardDragState(itemId: String) -> CardDragState {
        cardDragStates[itemId] ?? .idle
    }

    func getCardDissolveProgress(itemId: String) -> Double {
        cardDissolveProgress[itemId] ?? 0
    }

    func updateCardDragState(itemId: String, state: CardDragState) {
        let currentState = cardDragStates[itemId] ?? .idle
        guard !currentState.isEquivalentForRendering(to: state) else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = state.isDragging || currentState.isDragging
        withTransaction(transaction) {
            cardDragStates[itemId] = state
        }

        switch state {
        case .idle:
            if activeDropId == itemId {
                resetDropIndicator()
            }
        case .dragging:
            if activeDropId == itemId {
                resetDropIndicator()
            }
        case .nearBlackHole:
            handleCardNearCenter(itemId: itemId)
        case .releasedInBlackHole(let offset):
            handleCardReleasedInCenter(itemId: itemId, finalOffset: offset)
        case .dissolving:
            break
        }
    }

    private func handleCardNearCenter(itemId: String) {
        if activeDropId == itemId, airDropIndicatorState != .hidden {
            return
        }

        activeDropId = itemId

        if airDropIndicatorState == .hidden {
            airDropIndicatorState = .airdrop
            startAirDropToBlackHoleTimer()
        }
    }

    private func handleCardReleasedInCenter(itemId: String, finalOffset: CGSize) {
        cancelAirDropToBlackHoleTimer()

        guard let index = items.firstIndex(where: { $0.uniqueId == itemId }) else {
            resetDropIndicator()
            return
        }

        enum DropAction {
            case share
            case delete
            case none
        }

        let action: DropAction
        switch airDropIndicatorState {
        case .morphingToBlackHole, .blackHole:
            action = .delete
        case .airdrop:
            action = .share
        case .hidden:
            action = .none
        }

        switch action {
        case .delete:
            deleteItems([items[index].uniqueId])
            airDropIndicatorState = .blackHole
            cardDragStates[itemId] = .dissolving(offset: finalOffset)
            startDissolveAnimation(for: itemId) { [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    self.removeItem(withId: itemId)
                }
                if self.activeDropId == itemId {
                    self.resetDropIndicator()
                }
            }
        case .share:
            shareItem(at: index)
            resetDropIndicator()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                cardDragStates[itemId] = .idle
            }
        case .none:
            resetDropIndicator()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                cardDragStates[itemId] = .idle
            }
        }
    }

    private func shareItem(at index: Int) {
        let item = items[index]
        bridgeClient.fetchItemPayload(item.uniqueId) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let data):
                    do {
                        let payload = try self.decoder.decode(OrbitClipboardPayload.self, from: data)
                        ClipboardShareService.shared.share(payload: payload) { success in
                            if !success {
                                print("ClipboardRingViewModel: Share failed for \(payload.uniqueId)")
                            }
                        }
                    } catch {
                        print("ClipboardRingViewModel: Failed to decode payload: \(error)")
                    }
                case .failure(let error):
                    print("ClipboardRingViewModel: Fetch payload failed: \(error)")
                }
            }
        }
    }

    private func deleteItems(_ ids: [String]) {
        bridgeClient.deleteItems(ids) { result in
            if case .failure(let error) = result {
                print("ClipboardRingViewModel: Delete failed: \(error)")
            }
        }
    }

    private func startAirDropToBlackHoleTimer() {
        cancelAirDropToBlackHoleTimer()
        let dropTransitionSequenceId = UUID()
        self.dropTransitionSequenceId = dropTransitionSequenceId

        airDropToBlackHoleTimer = Timer.scheduledTimer(
            withTimeInterval: OrbitConfig.airDropToBlackHoleDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.dropTransitionSequenceId == dropTransitionSequenceId else { return }
                self.airDropIndicatorState = .morphingToBlackHole
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    guard self.dropTransitionSequenceId == dropTransitionSequenceId else { return }
                    self.airDropIndicatorState = .blackHole
                }
            }
        }
    }

    private func cancelAirDropToBlackHoleTimer() {
        dropTransitionSequenceId = UUID()
        airDropToBlackHoleTimer?.invalidate()
        airDropToBlackHoleTimer = nil
    }

    private func resetDropIndicator() {
        activeDropId = nil
        cancelAirDropToBlackHoleTimer()
        airDropIndicatorState = .hidden
    }

    private func startDissolveAnimation(for itemId: String, completion: @escaping () -> Void) {
        cardDissolveProgress[itemId] = 0
        let dissolveSequenceId = UUID()
        dissolveSequenceIds[itemId] = dissolveSequenceId

        let duration = OrbitConfig.dissolveDuration
        withAnimation(.linear(duration: duration)) {
            cardDissolveProgress[itemId] = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            guard self.dissolveSequenceIds[itemId] == dissolveSequenceId else { return }
            completion()
        }
    }

    private func removeItem(withId itemId: String) {
        guard let index = items.firstIndex(where: { $0.uniqueId == itemId }) else { return }

        cardDragStates.removeValue(forKey: itemId)
        cardDissolveProgress.removeValue(forKey: itemId)
        dissolveSequenceIds.removeValue(forKey: itemId)
        if index < cardAnimationProgress.count {
            cardAnimationProgress.remove(at: index)
        }

        if activeDropId == itemId {
            activeDropId = nil
        }

        items.remove(at: index)

        if selectedIndex == index {
            selectedIndex = items.isEmpty ? -1 : min(index, items.count - 1)
        } else if selectedIndex > index {
            selectedIndex -= 1
        }

        syncVisibleCardAnimationProgress()
    }

    private func syncVisibleCardAnimationProgress() {
        let count = visibleCount
        guard cardAnimationProgress.count != count else { return }
        let value = isFullyExpanded ? 1.0 : 0.0
        cardAnimationProgress = Array(repeating: value, count: count)
    }

    private func resetAnimationState() {
        animationSequenceId = UUID()
        dropTransitionSequenceId = UUID()
        cardAnimationProgress = Array(repeating: 0, count: visibleCount)
        isExpanding = false
        isFullyExpanded = false
        cardDragStates.removeAll()
        cardDissolveProgress.removeAll()
        dissolveSequenceIds.removeAll()
        resetDropIndicator()
    }
}
