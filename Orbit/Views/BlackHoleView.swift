//
//  BlackHoleView.swift
//  Orbit
//
//  Created by Claude on 1/8/26.
//

import SwiftUI

/// 黑洞视觉组件 - 使用图片素材
struct BlackHoleView: View {
    /// 是否显示
    let isVisible: Bool

    /// 旋转角度
    @State private var rotationAngle: Double = 0

    /// 脉冲缩放
    @State private var pulseScale: CGFloat = 1.0

    /// 黑洞大小
    private var size: CGFloat { OrbitConfig.blackHoleSize * 1.5 }

    var body: some View {
        ZStack {
            // 黑洞图片
            Image("black_hole_texture")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 1.5, height: size * 1.5)
                .rotationEffect(.degrees(rotationAngle))
                .scaleEffect(pulseScale)
                .shadow(color: Color.orange.opacity(0.3), radius: 30, x: 0, y: 0) // 添加光晕
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.1)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
        .onAppear {
            if isVisible {
                startAnimations()
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                startAnimations()
            } else {
                resetAnimationState()
            }
        }
        .onDisappear {
            resetAnimationState()
        }
    }

    private func startAnimations() {
        resetAnimationState()

        // 吸积盘旋转 - 缓慢旋转
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }

        // 脉冲动画
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
    }

    private func resetAnimationState() {
        rotationAngle = 0
        pulseScale = 1.0
    }
}


#Preview {
    ZStack {
        Color.black
        BlackHoleView(isVisible: true)
    }
    .frame(width: 400, height: 400)
}
