//
//  ClipboardRingView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import SwiftUI

struct ClipboardRingView: View {
    @ObservedObject var viewModel: ClipboardRingViewModel
    private static let dragCoordinateSpaceName = "ClipboardRingDragSpace"

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let displayItems = Array(viewModel.items.prefix(ClipboardRingViewModel.maxVisibleCards))
            let displayCount = displayItems.count
            let cardsLayer = Group {
                ForEach(Array(displayItems.enumerated()), id: \.element.uniqueId) { index, item in
                    let progress = viewModel.getCardAnimationProgress(index: index)
                    let layout = ArcLayout(
                        index: index,
                        totalCount: displayCount,
                        selectedIndex: viewModel.selectedIndex,
                        animationProgress: progress
                    )
                    let cardPosition = layout.cardPosition(relativeTo: center)
                    let dragState = viewModel.getCardDragState(itemId: item.uniqueId)

                    ClipboardCardView(
                        item: item,
                        index: index,
                        isSelected: index == viewModel.selectedIndex,
                        animationProgress: progress,
                        rotation: layout.cardRotation,
                        dragState: Binding(
                            get: { viewModel.getCardDragState(itemId: item.uniqueId) },
                            set: { viewModel.updateCardDragState(itemId: item.uniqueId, state: $0) }
                        ),
                        dissolveProgress: viewModel.getCardDissolveProgress(itemId: item.uniqueId),
                        originalPosition: cardPosition,
                        windowCenter: center,
                        windowBounds: CGRect(origin: .zero, size: geometry.size),
                        dragCoordinateSpaceName: Self.dragCoordinateSpaceName
                    )
                    .offset(y: -layout.radius)
                    .rotationEffect(.degrees(layout.orbitAngle))
                    .offset(dragState.offset)
                    .zIndex(layout.zIndex)
                    .onTapGesture {
                        guard viewModel.getCardDragState(itemId: item.uniqueId) == .idle else { return }
                        viewModel.selectByIndex(index)
                    }
                    .onHover { isHovering in
                        guard viewModel.getCardDragState(itemId: item.uniqueId) == .idle else { return }
                        if isHovering && viewModel.isFullyExpanded {
                            viewModel.selectByIndex(index)
                        }
                    }
                }
            }

            ZStack {
                if viewModel.airDropIndicatorState != .hidden {
                    AirDropIndicatorView(state: viewModel.airDropIndicatorState)
                        .position(center)
                        .zIndex(2000)
                }

                cardsLayer

                if viewModel.items.isEmpty {
                    emptyStateView
                        .position(center)
                        .zIndex(2002)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(center)
            .coordinateSpace(name: Self.dragCoordinateSpaceName)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            if viewModel.loadState == .loading {
                ProgressView()
                Text("Connecting to Deck...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.4))
            } else if viewModel.loadState == .empty {
                Text("No clipboard history")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.4))
            } else if case .failed(let message) = viewModel.loadState {
                Text("Deck unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.4))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}
