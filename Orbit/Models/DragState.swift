//
//  DragState.swift
//  Orbit
//
//  Created by Claude on 1/8/26.
//

import SwiftUI

/// 卡片拖拽状态
enum CardDragState: Equatable {
    /// 默认状态
    case idle
    /// 拖拽中，带有偏移量
    case dragging(offset: CGSize)
    /// 接近黑洞，显示抖动效果
    case nearBlackHole(offset: CGSize)
    /// 在黑洞区域释放（保留最终偏移量，不弹回）
    case releasedInBlackHole(offset: CGSize)
    /// 正在执行消散动画（保留偏移量）
    case dissolving(offset: CGSize)

    /// 是否正在拖拽（包括接近黑洞状态）
    var isDragging: Bool {
        switch self {
        case .dragging, .nearBlackHole:
            return true
        default:
            return false
        }
    }

    /// 检查是否是 releasedInBlackHole 状态（忽略 offset 值）
    var isReleasedInBlackHole: Bool {
        if case .releasedInBlackHole = self { return true }
        return false
    }

    /// 检查是否是 dissolving 状态（忽略 offset 值）
    var isDissolving: Bool {
        if case .dissolving = self { return true }
        return false
    }

    /// 获取当前偏移量
    var offset: CGSize {
        switch self {
        case .dragging(let offset), .nearBlackHole(let offset),
             .releasedInBlackHole(let offset), .dissolving(let offset):
            return offset
        default:
            return .zero
        }
    }

    /// 高频拖拽会在一帧内产生大量 sub-pixel offset 更新。
    /// 对拖拽中的连续 offset 做轻量去抖，避免整圈 SwiftUI ForEach 被无意义刷新。
    nonisolated func isEquivalentForRendering(to other: CardDragState, movementThreshold: CGFloat = 0.5) -> Bool {
        switch (self, other) {
        case (.idle, .idle):
            return true
        case (.dragging(let lhs), .dragging(let rhs)),
             (.nearBlackHole(let lhs), .nearBlackHole(let rhs)):
            return abs(lhs.width - rhs.width) < movementThreshold
                && abs(lhs.height - rhs.height) < movementThreshold
        case (.releasedInBlackHole(let lhs), .releasedInBlackHole(let rhs)),
             (.dissolving(let lhs), .dissolving(let rhs)):
            // 释放和消散需要保留精确落点，不能按阈值吞掉。
            return lhs == rhs
        default:
            return false
        }
    }
}

/// 文件拖拽状态
enum FileDragState: Equatable {
    /// 无文件拖拽
    case idle
    /// 文件进入窗口
    case entered(urls: [URL])
    /// 悬停在 AirDrop 区域
    case overAirDrop(urls: [URL])
    /// 悬停超时，变为黑洞
    case overBlackHole(urls: [URL])
    /// 正在处理（分享或删除）
    case processing

    /// 是否有文件拖拽进入
    var hasFiles: Bool {
        switch self {
        case .idle, .processing:
            return false
        default:
            return true
        }
    }

    /// 获取拖拽的文件 URLs
    var urls: [URL] {
        switch self {
        case .entered(let urls), .overAirDrop(let urls), .overBlackHole(let urls):
            return urls
        default:
            return []
        }
    }
}

/// AirDrop 指示器状态
enum AirDropIndicatorState: Equatable {
    /// 隐藏
    case hidden
    /// 显示 AirDrop 图标
    case airdrop
    /// 正在变形为黑洞
    case morphingToBlackHole
    /// 已变为黑洞
    case blackHole
}
