//
//  AirDropIndicatorView.swift
//  Orbit
//
//  Created by Claude on 1/8/26.
//

import SwiftUI

/// AirDrop 指示器视图
/// 显示系统 AirDrop 图标，支持脉冲动画和渐变到黑洞的过渡
struct AirDropIndicatorView: View {
    /// 当前状态
    let state: AirDropIndicatorState
    
    @Environment(\.colorScheme) private var colorScheme
    
    /// Determine if we should use dark mode appearance based on config
    private var isDark: Bool {
        switch OrbitConfig.cardMaterial {
        case .white:
            return false
        case .black:
            return true
        case .system, .liquidGlass:
            return colorScheme == .dark
        }
    }

    /// 脉冲缩放
    @State private var pulseScale: CGFloat = 1.0

    /// 变形进度 (0 = AirDrop, 1 = 黑洞)
    @State private var morphProgress: CGFloat = 0

    /// 图标大小
    private let iconSize: CGFloat = 60

    /// 主色调（白色/浅灰）
    private let primaryColor = Color.white
    /// 次要色调（灰色）
    private let secondaryColor = Color(white: 0.7)

    var body: some View {
        ZStack {
            // AirDrop 图标
            if state == .airdrop || state == .morphingToBlackHole {
                VStack(spacing: 12) {
                    // 背景圆形光晕 + 图标
                    ZStack {
                        // 磨砂背景确保可见性
                        Circle()
                            .fill(isDark ? AnyShapeStyle(Color(white: 0.28).opacity(0.9)) : AnyShapeStyle(.regularMaterial))
                            .frame(width: 100, height: 100)
                            .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 10, x: 0, y: 5)
                            .overlay(
                                Circle()
                                    .stroke(isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                            )

                        // 动态光晕
                        Circle()
                            .strokeBorder(
                                isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                lineWidth: 3
                            )
                            .frame(width: 90, height: 90)
                            .blur(radius: 2)
                            .scaleEffect(pulseScale)

                        // AirDrop 图标
                        Image(systemName: "airdrop")
                            .font(.system(size: 50, weight: .regular))
                            .foregroundStyle(isDark ? .white.opacity(0.9) : .black.opacity(0.8))
                    }

                    Text("Drop to Share")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isDark ? .white.opacity(0.9) : .black.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isDark ? AnyShapeStyle(Color(white: 0.28).opacity(0.9)) : AnyShapeStyle(.regularMaterial))
                                .shadow(color: .black.opacity(isDark ? 0.3 : 0.1), radius: 4, x: 0, y: 2)
                                .overlay(
                                    Capsule()
                                        .stroke(isDark ? Color.white.opacity(0.2) : Color.clear, lineWidth: 0.5)
                                )
                        )
                }
                .scaleEffect(pulseScale)
                .opacity(state == .morphingToBlackHole ? Double(1 - morphProgress) : 1)
            }

            // 黑洞（渐变出现）
            if state == .morphingToBlackHole || state == .blackHole {
                BlackHoleView(isVisible: true)
                    .opacity(state == .blackHole ? 1 : Double(morphProgress))
                    .scaleEffect(state == .blackHole ? 1 : morphProgress)
            }
        }
        .opacity(state == .hidden ? 0 : 1)
        .scaleEffect(state == .hidden ? 0.5 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
        .onAppear {
            handleStateChange(state)
        }
        .onChange(of: state) { _, newState in
            handleStateChange(newState)
        }
        .onDisappear {
            resetAnimationState()
        }
    }

    /// 开始脉冲动画
    private func startPulseAnimation() {
        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }

    /// 处理状态变化
    private func handleStateChange(_ newState: AirDropIndicatorState) {
        switch newState {
        case .hidden:
            resetAnimationState()

        case .airdrop:
            morphProgress = 0
            startPulseAnimation()

        case .morphingToBlackHole:
            pulseScale = 1.0
            // 开始变形动画
            withAnimation(.easeInOut(duration: 0.5)) {
                morphProgress = 1.0
            }

        case .blackHole:
            pulseScale = 1.0
            morphProgress = 1.0
        }
    }

    private func resetAnimationState() {
        pulseScale = 1.0
        morphProgress = 0
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var state: AirDropIndicatorState = .hidden

        var body: some View {
            VStack(spacing: 20) {
                ZStack {
                    Color.black.opacity(0.8)
                    AirDropIndicatorView(state: state)
                }
                .frame(width: 250, height: 250)

                HStack {
                    Button("Hidden") { state = .hidden }
                    Button("AirDrop") { state = .airdrop }
                    Button("Morphing") { state = .morphingToBlackHole }
                    Button("BlackHole") { state = .blackHole }
                }
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
