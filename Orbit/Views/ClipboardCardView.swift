//
//  ClipboardCardView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import AppKit
import SwiftUI

struct ClipboardCardView: View {
    private static let fileIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    let item: OrbitClipboardSummary
    let index: Int
    let isSelected: Bool
    let animationProgress: Double
    let rotation: Double

    @Binding var dragState: CardDragState
    let dissolveProgress: Double
    let originalPosition: CGPoint
    let windowCenter: CGPoint
    let windowBounds: CGRect
    let dragCoordinateSpaceName: String

    @Environment(\.colorScheme) private var colorScheme

    private var cardSize: CardSize { OrbitConfig.cardSize }
    private var iconSize: CGFloat { cardSize.iconSize * 0.9 }

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

    private var primaryTextColor: Color {
        isDarkCard ? Color.white.opacity(0.9) : Color(white: 0.15)
    }

    private var secondaryTextColor: Color {
        isDarkCard ? Color.white.opacity(0.6) : Color(white: 0.45)
    }

    private var usesLiquidGlass: Bool {
        guard OrbitConfig.cardMaterial == .liquidGlass,
              OrbitConfig.clipboardRingUsesLiquidGlass else {
            return false
        }
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    var body: some View {
        let horizontalPadding: CGFloat = cardSize == .small ? 12 : 14
        let verticalPadding: CGFloat = cardSize == .small ? 10 : 12
        let iconTextSpacing: CGFloat = cardSize == .small ? 4 : 6
        let textSpacing: CGFloat = 2
        let titleFontSize = max(9, cardSize.letterFontSize - 2)
        let subtitleFontSize = max(8, cardSize.letterFontSize - 4)
        let subtitleLimit = cardSize == .small ? 12 : 16
        let textMaxWidth = cardSize.cardWidth - (horizontalPadding * 2 + 8)
        let textAreaHeight = max(
            0,
            cardSize.cardHeight - (verticalPadding * 2) - iconSize - iconTextSpacing
        )
        let iconYOffset: CGFloat = -2
        let contentYOffset: CGFloat = 2

        OrbitCardView(
            isSelected: isSelected,
            animationProgress: animationProgress,
            rotation: rotation,
            dragState: $dragState,
            dissolveProgress: dissolveProgress,
            originalPosition: originalPosition,
            windowCenter: windowCenter,
            windowBounds: windowBounds,
            dragCoordinateSpaceName: dragCoordinateSpaceName,
            dropActivationRadius: OrbitConfig.centerDropRadius,
            usesLiquidGlass: usesLiquidGlass
        ) {
            VStack(spacing: iconTextSpacing) {
                iconView
                    .frame(width: iconSize, height: iconSize)
                    .offset(y: iconYOffset)

                ViewThatFits(in: .vertical) {
                    VStack(spacing: textSpacing) {
                        titleText(fontSize: titleFontSize, maxWidth: textMaxWidth)
                        subtitleText(fontSize: subtitleFontSize, maxWidth: textMaxWidth, limit: subtitleLimit)
                    }
                    titleText(fontSize: titleFontSize, maxWidth: textMaxWidth)
                }
                .frame(maxWidth: textMaxWidth, maxHeight: textAreaHeight, alignment: .center)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: contentYOffset)
        }
    }

    private var truncatedTitle: String {
        truncatedText(item.displayTitle, limit: 9)
    }

    private func titleText(fontSize: CGFloat, maxWidth: CGFloat) -> some View {
        Text(truncatedTitle)
            .font(.system(size: fontSize, weight: .regular))
            .foregroundColor(primaryTextColor)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: maxWidth, alignment: .center)
    }

    @ViewBuilder
    private func subtitleText(fontSize: CGFloat, maxWidth: CGFloat, limit: Int) -> some View {
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            Text(truncatedText(subtitle, limit: limit))
                .font(.system(size: fontSize, weight: .regular))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: maxWidth, alignment: .center)
        }
    }

    private func truncatedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "..."
    }

    @ViewBuilder
    private var iconView: some View {
        if let preview = item.previewImage, item.itemTypeValue == .image {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let fileIcon = fileIcon {
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: iconSize * 0.7, weight: .light))
                .foregroundColor(secondaryTextColor)
        }
    }

    private var fileIcon: NSImage? {
        guard let path = item.primaryFilePath else { return nil }
        let cacheKey = NSString(string: "\(path)#\(Int(iconSize.rounded(.up)))")
        if let cached = Self.fileIconCache.object(forKey: cacheKey) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        let preparedIcon = resizedImage(icon, to: NSSize(width: iconSize, height: iconSize))
        Self.fileIconCache.setObject(
            preparedIcon,
            forKey: cacheKey,
            cost: max(Int(iconSize.rounded(.up)), 1) * max(Int(iconSize.rounded(.up)), 1) * 4
        )
        return preparedIcon
    }

    private func resizedImage(_ image: NSImage, to size: NSSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return image }
        guard image.size.width > size.width || image.size.height > size.height else {
            return image
        }

        let resized = NSImage(size: size)
        resized.lockFocus()
        defer { resized.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        resized.isTemplate = image.isTemplate
        return resized
    }

    private var symbolName: String {
        switch item.itemTypeValue {
        case .text, .richText:
            return "doc.text"
        case .code:
            return "chevron.left.slash.chevron.right"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .url:
            return "link"
        case .color:
            return "paintpalette"
        }
    }
}
