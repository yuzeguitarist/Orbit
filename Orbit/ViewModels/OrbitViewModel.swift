//
//  OrbitViewModel.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import Combine
import Foundation
import SwiftUI

/// Orbit 主视图模型
/// 管理应用列表、选中状态、动画状态等
@MainActor
final class OrbitViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 当前运行的应用列表
    @Published private(set) var apps: [AppInfo] = []

    /// 当前选中的应用索引
    @Published var selectedIndex: Int = -1

    /// UI 是否正在展开动画中
    @Published var isExpanding = false

    /// UI 是否完全展开
    @Published var isFullyExpanded = false

    /// 每个卡片的动画进度（0-1）
    @Published var cardAnimationProgress: [Double] = []

    /// 鼠标锚点位置
    @Published var anchorPosition: CGPoint = .zero

    // MARK: - 拖拽相关属性

    /// 每个卡片的拖拽状态（Key = AppInfo.id）
    @Published private(set) var cardDragStates: [String: CardDragState] = [:]

    /// 每个卡片的消散进度（Key = AppInfo.id）
    @Published private(set) var cardDissolveProgress: [String: Double] = [:]

    /// 黑洞是否可见
    @Published var isBlackHoleVisible: Bool = false

    /// 文件拖拽状态
    @Published var fileDragState: FileDragState = .idle

    /// AirDrop 指示器状态
    @Published var airDropIndicatorState: AirDropIndicatorState = .hidden

    /// AirDrop 转黑洞的计时器
    private var airDropToBlackHoleTimer: Timer?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var letterMatchCache: [Character: [Int]] = [:] // 首字母匹配缓存
    private var currentLetterIndex: [Character: Int] = [:] // 当前字母循环索引
    private var contextAppId: String?
    private var animationSequenceId = UUID()
    private var dissolveSequenceIds: [String: UUID] = [:]
    private var dropTransitionSequenceId = UUID()

    private var visibleCount: Int {
        min(apps.count, OrbitConfig.maxVisibleCards)
    }

    // MARK: - Computed Properties

    /// 当前选中的应用
    var selectedApp: AppInfo? {
        guard selectedIndex >= 0 && selectedIndex < apps.count else { return nil }
        return apps[selectedIndex]
    }

    /// 应用数量
    var appCount: Int {
        apps.count
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    func setContextAppId(_ id: String?) {
        contextAppId = id
    }

    func resetPresentationState() {
        contextAppId = nil
        resetAnimationState()
    }

    /// 刷新应用列表
    func refreshApps(excludingProcessIdentifier: pid_t? = nil) {
        apps = AppListService.shared.getRunningApps(excludingProcessIdentifier: excludingProcessIdentifier)
        selectedIndex = -1
        resetAnimationState()
        buildLetterCache()
    }

    /// 设置锚点位置（鼠标位置）
    func setAnchorPosition(_ position: CGPoint) {
        anchorPosition = position
    }

    /// 开始展开动画 - 扇形旋转展开效果
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

        // 依次展开每个卡片，像扇子一样旋转展开
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

        // 动画完成后标记为完全展开
        let totalDuration = 0.4 / clampedSpeed + Double(count) * delayStep
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self else { return }
            guard self.animationSequenceId == animationSequenceId else { return }
            self.isExpanding = false
            self.isFullyExpanded = true
        }
    }

    /// 开始收起动画 - 扇形收拢效果
    func startCollapseAnimation(speed: Double = 1.0, completion: @escaping () -> Void) {
        let animationSequenceId = UUID()
        self.animationSequenceId = animationSequenceId
        isFullyExpanded = false
        let count = visibleCount
        let clampedSpeed = max(speed * OrbitConfig.ringAnimationSpeed, 0.1)
        let response = 0.3 / clampedSpeed
        let delayStep = 0.02 / clampedSpeed

        // 从最后一张卡片开始收起，逆向扇形收拢
        for i in (0 ..< count).reversed() {
            let delay = Double(count - 1 - i) * delayStep // 稍快的收起节奏
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.animationSequenceId == animationSequenceId else { return }
                guard i < self.cardAnimationProgress.count else { return }
                withAnimation(.spring(response: response, dampingFraction: 0.85)) {
                    self.cardAnimationProgress[i] = 0
                }
            }
        }

        // 收起完成回调
        let totalDuration = 0.35 / clampedSpeed + Double(count) * delayStep
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self else { return }
            guard self.animationSequenceId == animationSequenceId else { return }
            completion()
        }
    }

    // MARK: - Selection Methods

    /// 选择下一个（顺时针）
    func selectNext() {
        guard !apps.isEmpty else { return }
        if selectedIndex < 0 {
            selectedIndex = 0
            return
        }
        selectedIndex = (selectedIndex + 1) % apps.count
    }

    /// 选择上一个（逆时针）
    func selectPrevious() {
        guard !apps.isEmpty else { return }
        if selectedIndex < 0 {
            selectedIndex = apps.count - 1
            return
        }
        selectedIndex = (selectedIndex - 1 + apps.count) % apps.count
    }

    /// 通过数字选择（1-9）
    func selectByNumber(_ number: Int) {
        let index = number - 1 // 数字 1 对应索引 0
        guard index >= 0 && index < min(9, apps.count) else { return }
        selectedIndex = index
    }

    /// 通过索引直接选择
    func selectByIndex(_ index: Int) {
        guard index >= 0 && index < apps.count else { return }
        selectedIndex = index
    }

    /// 通过首字母选择
    /// - Returns: 是否匹配到应用
    func selectByLetter(_ letter: Character) -> Bool {
        let upperLetter = letter.uppercased().first ?? letter

        guard let matchingIndices = letterMatchCache[upperLetter], !matchingIndices.isEmpty else {
            return false // 无匹配
        }

        if OrbitConfig.enableLetterCycling {
            // 循环选择
            let currentCycleIndex = currentLetterIndex[upperLetter] ?? 0
            selectedIndex = matchingIndices[currentCycleIndex]
            currentLetterIndex[upperLetter] = (currentCycleIndex + 1) % matchingIndices.count
        } else {
            // 直接选择第一个匹配
            selectedIndex = matchingIndices[0]
        }
        return true
    }

    /// 激活当前选中的应用
    @discardableResult
    func activateSelectedApp() -> Bool {
        guard let app = selectedApp else { return false }
        let activated = app.activate()
        if activated, let fromAppId = contextAppId {
            let toAppId = app.id
            Task {
                await OrbitJumpModel.shared.recordTransition(from: fromAppId, to: toAppId)
            }
        }
        return activated
    }

    // MARK: - Keyboard Handling

    enum KeyPressResult {
        case unhandled
        case handled
        case activateAndDismiss
    }

    /// 处理键盘输入
    /// - Returns: 处理结果
    func handleKeyPress(
        _ keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> KeyPressResult {
        // Esc - 关闭
        if keyCode == 53 {
            return .unhandled // 让外层处理关闭
        }

        // Enter - 确认
        if keyCode == 36 {
            return .activateAndDismiss
        }

        // Tab - 切换
        if keyCode == 48 {
            if modifierFlags.contains(.shift) {
                selectPrevious()
            } else {
                selectNext()
            }
            return .handled
        }

        // 方向键
        switch keyCode {
        case 123: // 左箭头
            selectPrevious()
            return .handled
        case 124: // 右箭头
            selectNext()
            return .handled
        case 125: // 下箭头
            selectNext()
            return .handled
        case 126: // 上箭头
            selectPrevious()
            return .handled
        default:
            break
        }

        // 检查字符（优先使用忽略修饰键的字符，解决 Option/Control 下字符不稳定的问题）
        let primaryChar = characters?.first
        let fallbackChar = charactersIgnoringModifiers?.first
        let char: Character? = {
            if let fallback = fallbackChar, (fallback.isLetter || fallback.wholeNumberValue != nil) {
                return fallback
            }
            if let primary = primaryChar, (primary.isLetter || primary.wholeNumberValue != nil) {
                return primary
            }
            return fallbackChar ?? primaryChar
        }()
        guard let char = char else { return .unhandled }

        // 数字 1-9
        if let number = char.wholeNumberValue, number >= 1 && number <= 9 {
            selectByNumber(number)
            return .handled
        }

        // 字母快速跳转
        if char.isLetter {
            if selectByLetter(char) {
                return .handled
            }
            return .handled
        }

        return .unhandled
    }

    // MARK: - 卡片动画 / 拖拽对外接口（供 View 调用）

    func getCardAnimationProgress(index: Int) -> Double {
        index < cardAnimationProgress.count ? cardAnimationProgress[index] : 0
    }

    func getCardDragState(appId: String) -> CardDragState {
        cardDragStates[appId] ?? .idle
    }

    func getCardDissolveProgress(appId: String) -> Double {
        cardDissolveProgress[appId] ?? 0
    }

    func updateCardDragState(appId: String, state: CardDragState) {
        let currentState = cardDragStates[appId] ?? .idle
        guard !currentState.isEquivalentForRendering(to: state) else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = state.isDragging || currentState.isDragging
        withTransaction(transaction) {
            cardDragStates[appId] = state
        }

        if state.isDragging || state.isReleasedInBlackHole || state.isDissolving {
            isBlackHoleVisible = true
        } else if currentState.isDragging || currentState.isReleasedInBlackHole || currentState.isDissolving {
            isBlackHoleVisible = isAnyCardDragging
        }

        if state.isReleasedInBlackHole {
            handleCardReleasedInBlackHole(appId: appId, finalOffset: state.offset)
        }
    }

    // MARK: - Private Methods

    private func buildLetterCache() {
        letterMatchCache.removeAll()
        currentLetterIndex.removeAll()

        for (index, app) in apps.enumerated() {
            if let letter = app.firstLetter {
                if letterMatchCache[letter] == nil {
                    letterMatchCache[letter] = []
                }
                letterMatchCache[letter]?.append(index)
            }
        }
    }

    private func resetAnimationState() {
        animationSequenceId = UUID()
        dropTransitionSequenceId = UUID()
        cardAnimationProgress = Array(repeating: 0, count: visibleCount)
        isExpanding = false
        isFullyExpanded = false
        // 重置拖拽状态
        cardDragStates.removeAll()
        cardDissolveProgress.removeAll()
        dissolveSequenceIds.removeAll()
        isBlackHoleVisible = false
        fileDragState = .idle
        airDropIndicatorState = .hidden
        airDropToBlackHoleTimer?.invalidate()
        airDropToBlackHoleTimer = nil
    }

    private func syncVisibleCardAnimationProgress() {
        let count = visibleCount
        guard cardAnimationProgress.count != count else { return }
        let value = isFullyExpanded ? 1.0 : 0.0
        cardAnimationProgress = Array(repeating: value, count: count)
    }

    // MARK: - 卡片拖拽处理

    private var isAnyCardDragging: Bool {
        cardDragStates.values.contains { $0.isDragging }
    }

    private func handleCardReleasedInBlackHole(appId: String, finalOffset: CGSize) {
        guard let index = apps.firstIndex(where: { $0.id == appId }) else { return }
        let app = apps[index]

        // 1. 更新状态为消散中（保留偏移量，卡片停留在当前位置）
        cardDragStates[appId] = .dissolving(offset: finalOffset)

        // 2. 启动消散动画
        startDissolveAnimation(for: appId) { [weak self] in
            guard let self else { return }

            // 3. 动画完成后终止应用
            app.terminate { success in
                print("OrbitViewModel: App \(app.name) terminated: \(success)")
            }

            // 4. 从列表移除（带弹簧动画）
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                self.removeApp(withId: appId)
            }
        }
    }

    /// 启动消散动画
    private func startDissolveAnimation(for appId: String, completion: @escaping () -> Void) {
        cardDissolveProgress[appId] = 0
        let dissolveSequenceId = UUID()
        dissolveSequenceIds[appId] = dissolveSequenceId

        let duration = OrbitConfig.dissolveDuration
        withAnimation(.linear(duration: duration)) {
            cardDissolveProgress[appId] = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            guard self.dissolveSequenceIds[appId] == dissolveSequenceId else { return }
            completion()
        }
    }

    /// 从列表移除应用
    private func removeApp(withId appId: String) {
        guard let index = apps.firstIndex(where: { $0.id == appId }) else { return }

        // 清理该卡片的状态
        cardDragStates.removeValue(forKey: appId)
        cardDissolveProgress.removeValue(forKey: appId)
        dissolveSequenceIds.removeValue(forKey: appId)
        if index < cardAnimationProgress.count {
            cardAnimationProgress.remove(at: index)
        }

        // 移除应用
        apps.remove(at: index)

        // 更新选中索引
        if selectedIndex == index {
            selectedIndex = apps.isEmpty ? -1 : min(index, apps.count - 1)
        } else if selectedIndex > index {
            selectedIndex -= 1
        }

        // 重建字母缓存
        buildLetterCache()

        // 补齐可见进度，避免空位/闪烁
        syncVisibleCardAnimationProgress()

        isBlackHoleVisible = isAnyCardDragging
    }

    // MARK: - 文件拖拽处理

    /// 文件拖拽进入窗口
    func handleFileDragEntered(urls: [URL]) {
        fileDragState = .entered(urls: urls)

        // 如果扇子还没展开，触发展开
        if !isFullyExpanded && !isExpanding {
            startExpandAnimation()
        }
    }

    /// 文件拖拽位置更新
    func handleFileDragUpdated(isOverCenter: Bool) {
        guard case .entered(let urls) = fileDragState else {
            // 如果已经在 AirDrop 或黑洞状态，检查是否离开中心
            if !isOverCenter {
                cancelAirDropToBlackHoleTimer()
                if case .overAirDrop(let urls) = fileDragState {
                    fileDragState = .entered(urls: urls)
                    airDropIndicatorState = .hidden
                } else if case .overBlackHole(let urls) = fileDragState {
                    fileDragState = .entered(urls: urls)
                    airDropIndicatorState = .hidden
                }
            }
            return
        }

        if isOverCenter {
            // 进入中心区域，显示 AirDrop
            fileDragState = .overAirDrop(urls: urls)
            airDropIndicatorState = .airdrop
            startAirDropToBlackHoleTimer(urls: urls)
        }
    }

    /// 文件拖拽离开窗口
    func handleFileDragExited() {
        cancelAirDropToBlackHoleTimer()
        fileDragState = .idle
        airDropIndicatorState = .hidden
    }

    /// 文件拖拽释放
    func handleFileDragPerformed() -> Bool {
        switch fileDragState {
        case .overAirDrop(let urls):
            // 触发 AirDrop
            cancelAirDropToBlackHoleTimer()
            fileDragState = .processing
            airDropIndicatorState = .hidden

            FileDragDropService.shared.shareViaAirDrop(urls: urls) { [weak self] success in
                Task { @MainActor in
                    self?.fileDragState = .idle
                }
            }
            return true

        case .overBlackHole(let urls):
            // 移动到废纸篓
            cancelAirDropToBlackHoleTimer()
            fileDragState = .processing
            airDropIndicatorState = .hidden

            FileDragDropService.shared.moveToTrash(urls: urls) { [weak self] success, error in
                Task { @MainActor in
                    self?.fileDragState = .idle
                    if let error = error {
                        print("OrbitViewModel: Failed to move files to trash: \(error)")
                    }
                }
            }
            return true

        default:
            fileDragState = .idle
            airDropIndicatorState = .hidden
            return false
        }
    }

    /// 启动 AirDrop 转黑洞计时器
    private func startAirDropToBlackHoleTimer(urls: [URL]) {
        cancelAirDropToBlackHoleTimer()
        let dropTransitionSequenceId = UUID()
        self.dropTransitionSequenceId = dropTransitionSequenceId

        airDropToBlackHoleTimer = Timer.scheduledTimer(
            withTimeInterval: OrbitConfig.airDropToBlackHoleDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.dropTransitionSequenceId == dropTransitionSequenceId else { return }
                // 开始变形动画
                self.airDropIndicatorState = .morphingToBlackHole

                // 变形完成后切换到黑洞状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    guard self.dropTransitionSequenceId == dropTransitionSequenceId else { return }
                    self.fileDragState = .overBlackHole(urls: urls)
                    self.airDropIndicatorState = .blackHole
                }
            }
        }
    }

    /// 取消 AirDrop 转黑洞计时器
    private func cancelAirDropToBlackHoleTimer() {
        dropTransitionSequenceId = UUID()
        airDropToBlackHoleTimer?.invalidate()
        airDropToBlackHoleTimer = nil
    }
}
