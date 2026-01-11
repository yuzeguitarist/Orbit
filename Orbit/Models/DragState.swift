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
