//
//  OrbitRingView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import SwiftUI

/// C形环布局 - 卡片像旋转楼梯层叠
struct OrbitRingView: View {
    @ObservedObject var viewModel: OrbitViewModel
    let onDismiss: () -> Void
    private static let dragCoordinateSpaceName = "OrbitRingDragSpace"

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let displayApps = Array(viewModel.apps.prefix(OrbitConfig.maxVisibleCards))
            let displayCount = displayApps.count
            let cardsLayer = Group {
                ForEach(Array(displayApps.enumerated()), id: \.element.id) { index, app in
                    let progress = viewModel.getCardAnimationProgress(index: index)

                    // 将动画进度传入 ArcLayout，实现扇形展开
                    let layout = ArcLayout(
                        index: index,
                        totalCount: displayCount,
                        selectedIndex: viewModel.selectedIndex,
                        animationProgress: progress
                    )

                    // 计算卡片的原始位置（用于拖拽距离计算）
                    let cardPosition = layout.cardPosition(relativeTo: center)
                    let dragState = viewModel.getCardDragState(appId: app.id)

                    // 使用旋转方式实现圆弧路径动画
                    // 卡片先放到正上方（offset），然后绕中心旋转到目标角度
                    AppCardView(
                        app: app,
                        index: index,
                        isSelected: index == viewModel.selectedIndex,
                        animationProgress: progress,
                        rotation: layout.cardRotation,
                        orbitAngle: layout.orbitAngle,
                        dragState: Binding(
                            get: { viewModel.getCardDragState(appId: app.id) },
                            set: { viewModel.updateCardDragState(appId: app.id, state: $0) }
                        ),
                        dissolveProgress: viewModel.getCardDissolveProgress(appId: app.id),
                        originalPosition: cardPosition,
                        windowCenter: center,
                        windowBounds: CGRect(origin: .zero, size: geometry.size),
                        dragCoordinateSpaceName: Self.dragCoordinateSpaceName
                    )
                    .offset(y: -layout.radius) // 卡片放在正上方，距离中心 radius
                    .rotationEffect(.degrees(layout.orbitAngle)) // 绕中心旋转到目标位置
                    .offset(dragState.offset)
                    .zIndex(layout.zIndex)
                    .onTapGesture {
                        // 只有在非拖拽状态下才响应点击
                        guard viewModel.getCardDragState(appId: app.id) == .idle else { return }
                        viewModel.selectByIndex(index)
                        viewModel.activateSelectedApp()
                        onDismiss()
                    }
                    .onHover { isHovering in
                        // 只有在非拖拽状态下才响应悬停
                        guard viewModel.getCardDragState(appId: app.id) == .idle else { return }
                        if isHovering && viewModel.isFullyExpanded {
                            viewModel.selectByIndex(index)
                        }
                    }
                }
            }

            ZStack {
                // 黑洞（卡片拖拽时显示）- 必须在所有卡片之上
                if viewModel.isBlackHoleVisible {
                    BlackHoleView(isVisible: true)
                        .position(center)
                        .zIndex(2000)
                }

                // AirDrop 指示器（文件拖拽时显示）
                if viewModel.airDropIndicatorState != .hidden {
                    AirDropIndicatorView(state: viewModel.airDropIndicatorState)
                        .position(center)
                        .zIndex(2001)
                }

                cardsLayer

                // 中心应用名称（仅当无拖拽且无文件拖拽时显示）
                if viewModel.isFullyExpanded,
                   !viewModel.isBlackHoleVisible,
                   viewModel.airDropIndicatorState == .hidden,
                   let selectedApp = viewModel.selectedApp
                {
                    Text(selectedApp.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.3))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 100)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.1), value: viewModel.selectedIndex)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(center)
            .coordinateSpace(name: Self.dragCoordinateSpaceName)
        }
        .onAppear {
            viewModel.startExpandAnimation()
        }
    }
}
