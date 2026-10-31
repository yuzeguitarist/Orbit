//
//  OrbitConfig.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import AppKit
import Foundation
import SwiftUI

struct TriggerShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let keyLabel: String

    static let allowedModifierFlags: NSEvent.ModifierFlags = [
        .control,
        .option,
        .shift,
        .command
    ]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifierFlags)
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.allowedModifierFlags)
        let label = TriggerShortcut.label(for: event.keyCode, characters: event.charactersIgnoringModifiers)
        self.init(keyCode: event.keyCode, modifiers: modifiers, keyLabel: label)
    }

    var displayString: String {
        TriggerShortcut.modifierSymbols(from: modifiers) + keyLabel
    }

    static func == (lhs: TriggerShortcut, rhs: TriggerShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    static func label(for keyCode: UInt16, characters: String?) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }

        if let characters, !characters.isEmpty {
            if characters == " " {
                return specialKeyLabels[49] ?? "Space"
            }
            return characters.uppercased()
        }

        return "Key \(keyCode)"
    }

    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    private static let specialKeyLabels: [UInt16: String] = [
        49: "Space",
        36: "Return",
        48: "Tab",
        53: "Esc",
        51: "Delete",
        117: "Forward Delete",
        76: "Enter",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        115: "Home",
        119: "End",
        116: "Page Up",
        121: "Page Down",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20",
        71: "Clear",
        114: "Help"
    ]
}

/// 卡片大小选项
enum CardSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extraLarge"

    /// 本地化显示名称
    var localizedName: String {
        NSLocalizedString("cardSize.\(rawValue)", comment: "")
    }

    /// 卡片宽度
    var cardWidth: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 130
        case .large: return 160
        case .extraLarge: return 190
        }
    }

    /// 卡片高度
    var cardHeight: CGFloat {
        switch self {
        case .small: return 92
        case .medium: return 120
        case .large: return 148
        case .extraLarge: return 175
        }
    }

    /// 图标尺寸
    var iconSize: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 52
        case .large: return 64
        case .extraLarge: return 76
        }
    }

    /// 字母字体大小
    var letterFontSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 15
        case .extraLarge: return 17
        }
    }

    /// 圆环半径
    var orbitRadius: CGFloat {
        switch self {
        case .small: return 140
        case .medium: return 170
        case .large: return 200
        case .extraLarge: return 230
        }
    }

    /// 图标偏移量 X
    var iconOffsetX: CGFloat {
        return 0
    }

    /// 图标偏移量 Y
    var iconOffsetY: CGFloat {
        return 0
    }

    /// 弧线高度
    var arcHeight: CGFloat {
        switch self {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        case .extraLarge: return 12
        }
    }

    /// 窗口大小（需要容纳圆环和卡片）
    var windowSize: CGFloat {
        switch self {
        case .small: return 500
        case .medium: return 600
        case .large: return 700
        case .extraLarge: return 800
        }
    }
}

/// Orbit 应用的全局配置
struct OrbitConfig {
    // MARK: - 触发配置

    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["ORBIT_UI_TEST_DEFAULTS_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        #endif
        return .standard
    }

    enum DefaultsKey {
        static let longPressThreshold = "orbit.longPressThreshold"
        static let triggerModifier = "orbit.triggerModifier"
        static let cmdTabShortcutEnabled = "orbit.cmdTabShortcutEnabled"
        static let cardSize = "orbit.cardSize"
        static let lockRingToScreenCenter = "orbit.lockRingToScreenCenter"
        static let lockRingItemsUpright = "orbit.lockRingItemsUpright"
        static let clipboardRingUsesLiquidGlass = "orbit.clipboardRingUsesLiquidGlass"
        static let ringAnimationSpeed = "orbit.ringAnimationSpeed"
    }

    /// 长按触发阈值（毫秒）
    static let defaultLongPressThreshold: TimeInterval = 150
    static let defaultRingAnimationSpeed: Double = 1.0
    static let cmdTabShortcut = TriggerShortcut(
        keyCode: 48,
        modifiers: .command,
        keyLabel: TriggerShortcut.label(for: 48, characters: nil)
    )

    static var longPressThreshold: TimeInterval {
        get {
            let stored = defaults.double(forKey: DefaultsKey.longPressThreshold)
            return stored > 0 ? stored : defaultLongPressThreshold
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.longPressThreshold)
        }
    }

    /// 触发用的修饰键
    static var triggerModifier: TriggerModifier {
        get {
            let stored = defaults.string(forKey: DefaultsKey.triggerModifier)
            return TriggerModifier(rawValue: stored ?? "") ?? .option
        }
        set {
            defaults.set(newValue.rawValue, forKey: DefaultsKey.triggerModifier)
        }
    }

    static var isCmdTabShortcutEnabled: Bool {
        get {
            defaults.object(forKey: DefaultsKey.cmdTabShortcutEnabled) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.cmdTabShortcutEnabled)
        }
    }

    static var isLongPressEnabled: Bool {
        triggerModifier != .disabled
    }

    static func triggerHelpText(longPressKey: String, shortcutKey: String, disabledKey: String) -> String {
        if let customShortcut {
            return String(format: NSLocalizedString(shortcutKey, comment: ""), customShortcut.displayString)
        }
        if isCmdTabShortcutEnabled {
            return String(format: NSLocalizedString(shortcutKey, comment: ""), cmdTabShortcut.displayString)
        }
        if triggerModifier == .disabled {
            return NSLocalizedString(disabledKey, comment: "")
        }
        let key = modifierTriggerMode == .doubleTapAndHold ? longPressKey + ".double" : longPressKey
        return String(format: NSLocalizedString(key, comment: ""), triggerModifier.symbol)
    }

    /// 卡片大小
    static var cardSize: CardSize {
        get {
            let stored = defaults.string(forKey: DefaultsKey.cardSize)
            return CardSize(rawValue: stored ?? "") ?? .medium
        }
        set {
            defaults.set(newValue.rawValue, forKey: DefaultsKey.cardSize)
        }
    }

    /// 圆环是否固定在屏幕中心
    static var lockRingToScreenCenter: Bool {
        get {
            defaults.bool(forKey: DefaultsKey.lockRingToScreenCenter)
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.lockRingToScreenCenter)
        }
    }

    /// 圆环卡片内容朝向是否保持朝上
    static var lockRingItemsUpright: Bool {
        get {
            defaults.bool(forKey: DefaultsKey.lockRingItemsUpright)
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.lockRingItemsUpright)
        }
    }

    /// 剪贴板圆环是否启用 Liquid Glass
    static var clipboardRingUsesLiquidGlass: Bool {
        get {
            defaults.bool(forKey: DefaultsKey.clipboardRingUsesLiquidGlass)
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.clipboardRingUsesLiquidGlass)
        }
    }

    /// 圆环动画速度倍率（1.0 为默认速度）
    static var ringAnimationSpeed: Double {
        get {
            let stored = defaults.double(forKey: DefaultsKey.ringAnimationSpeed)
            return stored > 0 ? stored : defaultRingAnimationSpeed
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.ringAnimationSpeed)
        }
    }

    /// 卡片材质
    enum CardMaterial: String, CaseIterable, Identifiable {
        case system = "system"
        case white = "white"
        case black = "black"
        case liquidGlass = "liquidGlass"

        var id: String { rawValue }

        var localizedName: String {
            NSLocalizedString("cardMaterial.\(rawValue)", comment: "")
        }
    }

    static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    static var availableCardMaterials: [CardMaterial] {
        guard isLiquidGlassAvailable else {
            return CardMaterial.allCases.filter { $0 != .liquidGlass }
        }
        return CardMaterial.allCases
    }

    /// 当前卡片材质
    static var cardMaterial: CardMaterial {
        get {
            let stored = defaults.string(forKey: "orbit.cardMaterial")
            let material = CardMaterial(rawValue: stored ?? "") ?? .system
            if material == .liquidGlass, !isLiquidGlassAvailable {
                return .system
            }
            return material
        }
        set {
            defaults.set(newValue.rawValue, forKey: "orbit.cardMaterial")
        }
    }

    // MARK: - UI 布局配置

    /// 环形内半径
    static var innerRadius: CGFloat = 80

    /// 环形外半径
    static var outerRadius: CGFloat = 180

    /// 图标尺寸
    static var iconSize: CGFloat = 52

    /// 起始角度（度数，0度为右侧，顺时针）
    static var startAngle: Double = -120

    /// 结束角度（度数）- 形成C形开口
    static var endAngle: Double = 120

    /// 卡片间隙角度
    static var cardGap: Double = 2

    /// 最大显示卡片数
    static var maxVisibleCards: Int = 12

    // MARK: - 动画配置

    /// 展开动画总时长（秒）
    static var expandDuration: TimeInterval = 0.25

    /// 收起动画时长
    static var collapseDuration: TimeInterval = 0.15

    /// 选中切换动画时长
    static var selectionDuration: TimeInterval = 0.1

    /// 卡片展开间隔延迟（扇形展开时每张卡片的延迟）
    static var cardStaggerDelay: TimeInterval = 0.02

    /// 关闭收起动画加速倍率（>1 更快）
    static var dismissCollapseSpeed: Double = 1.2

    // MARK: - 视觉效果配置（黑白灰）

    /// 卡片背景色（深灰）
    static var cardBackgroundColor: Color = Color(white: 0.25)

    /// 卡片高亮背景色（稍亮的灰）
    static var cardHighlightColor: Color = Color(white: 0.35)

    /// 卡片边缘色（更深）
    static var cardEdgeColor: Color = Color(white: 0.15)

    /// 选中卡片背景色
    static var selectedCardColor: Color = Color(white: 0.4)

    /// 文字颜色
    static var textColor: Color = Color(white: 0.9)

    /// 次要文字颜色
    static var secondaryTextColor: Color = Color(white: 0.6)

    // MARK: - 键盘映射配置

    /// 是否启用字母循环选择
    static var enableLetterCycling: Bool = true

    // MARK: - 黑洞配置

    /// 黑洞大小
    static var blackHoleSize: CGFloat = 80

    /// 黑洞激活半径（卡片中心距离窗口中心小于此值时触发抖动）
    static var blackHoleActivationRadius: CGFloat = 60

    /// 黑洞发光颜色（金橙色）
    static var blackHoleGlowColor: Color = Color(red: 1.0, green: 0.75, blue: 0.3)

    // MARK: - 消散效果配置

    /// 消散动画时长（秒）
    static var dissolveDuration: TimeInterval = 0.8

    /// 消散粒子数量
    static var dissolveParticleCount: Int = 80

    // MARK: - 应用终止配置

    /// 优雅退出等待时间（秒），超时后强制退出
    static var terminateGracePeriod: TimeInterval = 2.0

    // MARK: - 文件拖拽配置

    /// AirDrop 转黑洞的等待时间（秒）
    static var airDropToBlackHoleDelay: TimeInterval = 1.5

    /// 中心区域半径（文件拖入此区域触发操作）
    static var centerDropRadius: CGFloat = 80
}
