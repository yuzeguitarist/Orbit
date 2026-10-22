//
//  OrbitCardView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import SwiftUI

struct OrbitCardView<Content: View>: View {
    let isSelected: Bool
    let animationProgress: Double
    let rotation: Double
    @Binding var dragState: CardDragState
    let dissolveProgress: Double
    let originalPosition: CGPoint
    let windowCenter: CGPoint
    let windowBounds: CGRect
    let dragCoordinateSpaceName: String
    let dropActivationRadius: CGFloat
    let usesLiquidGlass: Bool
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    @State private var shakeOffset: CGFloat = 0
    @State private var shakeTimer: Timer?

    @State private var isDragActive = false
    @State private var constrainedOffset: CGSize = .zero
    @State private var lastTranslation: CGSize = .zero

    private var cardSize: CardSize { OrbitConfig.cardSize }
    private var cardWidth: CGFloat { cardSize.cardWidth }
    private var cardHeight: CGFloat { cardSize.cardHeight }
    private let slantAngle: Double = 10
    private var edgeResistanceRange: CGFloat { max(120, cardWidth) }
    private var edgeInset: CGFloat { max(35, cardWidth * 0.25) }

    private var isDarkCard: Bool {
        switch OrbitConfig.cardMaterial {
        case .white:
            return false
        case .black:
            return true
        case .system, .liquidGlass:
            return colorScheme == .dark
        }
    }

    private var cardBackgroundColor: Color {
        if isDarkCard {
            return Color(white: 0.22)
        }
        return .white
    }

    private var cardBorderColor: Color {
        if isDarkCard {
            return isSelected ? Color(white: 0.9) : Color(white: 0.35)
        }
        return Color(white: isSelected ? 0.45 : 0.85)
    }

    private var cardShadowColor: Color {
        if isDarkCard {
            return Color.black.opacity(isSelected ? 0.5 : 0.35)
        }
        return Color.black.opacity(isSelected ? 0.22 : 0.14)
    }

    private var cardShadowRadius: CGFloat {
        isSelected ? 14 : 8
    }

    private var cardShadowYOffset: CGFloat {
        isSelected ? 6 : 4
    }

    private var isUsingLiquidGlass: Bool {
        if usesLiquidGlass {
            if #available(macOS 26.0, *) {
                return true
            }
        }
        return false
    }

    // Hide non-selected cards while they are still stacked at the origin.
    private var visibilityOpacity: Double {
        let epsilon = 0.0001
        if animationProgress <= epsilon {
            return isSelected ? 1 : 0
        }

        if isSelected { return 1 }

        let fadeStart = 0.02
        let fadeDuration = 0.12
        if animationProgress <= fadeStart { return 0 }

        let t = (animationProgress - fadeStart) / fadeDuration
        return min(1, max(0, t))
    }

    init(
        isSelected: Bool,
        animationProgress: Double,
        rotation: Double,
        dragState: Binding<CardDragState>,
        dissolveProgress: Double,
        originalPosition: CGPoint,
        windowCenter: CGPoint,
        windowBounds: CGRect,
        dragCoordinateSpaceName: String,
        dropActivationRadius: CGFloat = OrbitConfig.blackHoleActivationRadius,
        usesLiquidGlass: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.animationProgress = animationProgress
        self.rotation = rotation
        self._dragState = dragState
        self.dissolveProgress = dissolveProgress
        self.originalPosition = originalPosition
        self.windowCenter = windowCenter
        self.windowBounds = windowBounds
        self.dragCoordinateSpaceName = dragCoordinateSpaceName
        self.dropActivationRadius = dropActivationRadius
        self.usesLiquidGlass = usesLiquidGlass
        self.content = content()
    }

    private func distanceToCenter(with offset: CGSize) -> CGFloat {
        let currentX = originalPosition.x + offset.width
        let currentY = originalPosition.y + offset.height
        let dx = currentX - windowCenter.x
        let dy = currentY - windowCenter.y
        return sqrt(dx * dx + dy * dy)
    }

    private var blackHoleDirection: Double {
        let dx = windowCenter.x - originalPosition.x
        let dy = windowCenter.y - originalPosition.y
        return atan2(Double(dy), Double(dx))
    }

    private var shakeRotation: Double {
        (dragState == .nearBlackHole(offset: .zero) || isNearDropTarget) ? Double(shakeOffset) : 0
    }

    private var appliedRotation: Double {
        rotation + shakeRotation
    }

    var body: some View {
        let cardShape = ArcTrapezoidShape(slantAngle: slantAngle)

        ZStack {
            cardSurface(cardShape: cardShape)

            cardShape
                .stroke(cardBorderColor, lineWidth: isSelected ? 2.0 : 0.8)
                .shadow(color: (isSelected && isDarkCard) ? Color.white.opacity(0.25) : .clear, radius: 10, x: 0, y: 0)

            content
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(cardShape)
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: cardShadowYOffset)
        .rotationEffect(.degrees(appliedRotation))
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .opacity(visibilityOpacity)
        .allowsHitTesting(visibilityOpacity > 0.01)
        .pixelDissolve(progress: dissolveProgress, blackHoleDirection: blackHoleDirection)
        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isSelected)
        .gesture(dragGesture)
        .onChange(of: dragState) { _, newState in
            handleDragStateChange(newState)
        }
        .onDisappear {
            stopShakeAnimation()
            resetDragTracking()
        }
    }

    private var isNearDropTarget: Bool {
        if case .nearBlackHole = dragState {
            return true
        }
        return false
    }

    @ViewBuilder
    private func cardSurface(cardShape: ArcTrapezoidShape) -> some View {
        if usesLiquidGlass {
            if #available(macOS 26.0, *) {
                liquidGlassSurface(cardShape: cardShape)
            } else {
                cardShape
                    .fill(cardBackgroundColor)
            }
        } else {
            cardShape
                .fill(cardBackgroundColor)
        }
    }

    @available(macOS 26.0, *)
    private func liquidGlassSurface(cardShape: ArcTrapezoidShape) -> some View {
        Color.clear
            .glassEffect(Glass.regular, in: cardShape)
            .clipShape(cardShape)
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named(dragCoordinateSpaceName))
            .onChanged { value in
                if !isDragActive {
                    isDragActive = true
                    constrainedOffset = dragState.offset
                    lastTranslation = .zero
                }

                let delta = CGSize(
                    width: value.translation.width - lastTranslation.width,
                    height: value.translation.height - lastTranslation.height
                )
                lastTranslation = value.translation

                let adjustedDelta = applyEdgeResistance(to: delta, currentOffset: constrainedOffset)
                constrainedOffset = CGSize(
                    width: constrainedOffset.width + adjustedDelta.width,
                    height: constrainedOffset.height + adjustedDelta.height
                )
                constrainedOffset = clampOffsetToBounds(constrainedOffset)

                let offset = constrainedOffset
                let distance = distanceToCenter(with: offset)

                if distance < dropActivationRadius {
                    if !isNearDropTarget {
                        dragState = .nearBlackHole(offset: offset)
                        startShakeAnimation()
                    } else {
                        dragState = .nearBlackHole(offset: offset)
                    }
                } else {
                    if isNearDropTarget {
                        stopShakeAnimation()
                    }
                    dragState = .dragging(offset: offset)
                }
            }
            .onEnded { _ in
                let offset = constrainedOffset
                let distance = distanceToCenter(with: offset)

                stopShakeAnimation()
                resetDragTracking()

                if distance < dropActivationRadius {
                    dragState = .releasedInBlackHole(offset: offset)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragState = .idle
                    }
                }
            }
    }

    private func applyEdgeResistance(to delta: CGSize, currentOffset: CGSize) -> CGSize {
        guard windowBounds.width > 0, windowBounds.height > 0 else {
            return delta
        }

        let currentX = originalPosition.x + currentOffset.width
        let currentY = originalPosition.y + currentOffset.height
        let baseVector = CGVector(dx: currentX - windowCenter.x, dy: currentY - windowCenter.y)
        let baseRadius = sqrt(baseVector.dx * baseVector.dx + baseVector.dy * baseVector.dy)
        guard baseRadius > 0.0001 else { return delta }

        let outward = CGVector(dx: baseVector.dx / baseRadius, dy: baseVector.dy / baseRadius)
        let deltaVector = CGVector(dx: delta.width, dy: delta.height)
        let radial = deltaVector.dx * outward.dx + deltaVector.dy * outward.dy
        let tangential = CGVector(
            dx: deltaVector.dx - radial * outward.dx,
            dy: deltaVector.dy - radial * outward.dy
        )

        var adjustedRadial = radial
        if radial > 0 {
            let maxRadius = maxRadiusAlong(direction: outward, fallbackRadius: baseRadius)
            let remaining = max(0, maxRadius - baseRadius)
            if remaining < edgeResistanceRange {
                let factor = max(0, remaining / edgeResistanceRange)
                adjustedRadial = radial * factor
            }
        }

        return CGSize(
            width: tangential.dx + adjustedRadial * outward.dx,
            height: tangential.dy + adjustedRadial * outward.dy
        )
    }

    private func maxRadiusAlong(direction: CGVector, fallbackRadius: CGFloat) -> CGFloat {
        let safeBounds = windowBounds.insetBy(
            dx: cardWidth * 0.5 + edgeInset,
            dy: cardHeight * 0.5 + edgeInset
        )
        guard safeBounds.width > 0, safeBounds.height > 0 else { return fallbackRadius }

        var candidates: [CGFloat] = []
        if abs(direction.dx) > 0.0001 {
            candidates.append((safeBounds.minX - windowCenter.x) / direction.dx)
            candidates.append((safeBounds.maxX - windowCenter.x) / direction.dx)
        }
        if abs(direction.dy) > 0.0001 {
            candidates.append((safeBounds.minY - windowCenter.y) / direction.dy)
            candidates.append((safeBounds.maxY - windowCenter.y) / direction.dy)
        }

        let positive = candidates.filter { $0 > 0 }
        return positive.min() ?? fallbackRadius
    }

    private func clampOffsetToBounds(_ offset: CGSize) -> CGSize {
        let safeBounds = windowBounds.insetBy(
            dx: cardWidth * 0.5 + edgeInset,
            dy: cardHeight * 0.5 + edgeInset
        )
        guard safeBounds.width > 0, safeBounds.height > 0 else { return offset }

        let centerX = originalPosition.x + offset.width
        let centerY = originalPosition.y + offset.height
        let clampedX = min(max(centerX, safeBounds.minX), safeBounds.maxX)
        let clampedY = min(max(centerY, safeBounds.minY), safeBounds.maxY)
        return CGSize(width: clampedX - originalPosition.x, height: clampedY - originalPosition.y)
    }

    private func resetDragTracking() {
        isDragActive = false
        constrainedOffset = .zero
        lastTranslation = .zero
    }

    private func startShakeAnimation() {
        shakeTimer?.invalidate()
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.linear(duration: 0.05)) {
                    shakeOffset = shakeOffset > 0 ? -3 : 3
                }
            }
        }
    }

    private func stopShakeAnimation() {
        shakeTimer?.invalidate()
        shakeTimer = nil
        withAnimation(.linear(duration: 0.05)) {
            shakeOffset = 0
        }
    }

    private func handleDragStateChange(_ newState: CardDragState) {
        switch newState {
        case .nearBlackHole:
            if shakeTimer == nil {
                startShakeAnimation()
            }
        case .idle, .dragging, .releasedInBlackHole, .dissolving:
            stopShakeAnimation()
        }
    }
}
