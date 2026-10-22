//
//  PixelDissolveEffect.swift
//  Orbit
//
//  Created by Claude on 1/8/26.
//

import SwiftUI

/// 像素化消散效果（Thanos snap 风格）
/// 将视图分解成粒子并向黑洞方向飘散
struct PixelDissolveModifier: ViewModifier {
    /// 消散进度 (0 = 完整, 1 = 完全消散)
    let progress: Double

    /// 黑洞方向（相对于视图中心的角度，弧度）
    let blackHoleDirection: Double

    /// 粒子数量
    private var particleCount: Int { OrbitConfig.dissolveParticleCount }

    /// 随机种子（用于生成一致的粒子位置）
    @State private var particleSeeds: [ParticleSeed] = []

    struct ParticleSeed: Identifiable {
        let id: Int
        let startX: CGFloat
        let startY: CGFloat
        let angle: Double
        let speed: CGFloat
        let delay: Double
        let size: CGFloat
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if progress <= 0.001 {
            content
        } else {
            content
                .opacity(progress < 0.1 ? 1 : max(0, 1 - progress * 1.2))
                .background(
                    GeometryReader { geo in
                        Canvas { context, size in
                            guard progress > 0.05 else { return }

                            for seed in particleSeeds {
                                let adjustedProgress = max(0, (progress - seed.delay) / (1 - seed.delay))
                                guard adjustedProgress > 0 else { continue }

                                let moveDistance = seed.speed * CGFloat(adjustedProgress) * 100
                                let currentX = seed.startX + cos(seed.angle) * moveDistance
                                let currentY = seed.startY + sin(seed.angle) * moveDistance

                                let alpha = max(0, 1 - adjustedProgress * 1.5)
                                let currentSize = seed.size * CGFloat(1 - adjustedProgress * 0.5)
                                let rect = CGRect(
                                    x: currentX - currentSize / 2,
                                    y: currentY - currentSize / 2,
                                    width: currentSize,
                                    height: currentSize
                                )

                                context.opacity = alpha
                                let particleColor = Color(red: 1.0, green: 0.75 + Double(seed.id % 10) * 0.02, blue: 0.3)
                                context.fill(
                                    Path(ellipseIn: rect),
                                    with: .color(particleColor.opacity(0.9))
                                )
                            }
                        }
                        .onAppear {
                            generateParticles(in: geo.size)
                        }
                    }
                )
                .blur(radius: progress * 2)
        }
    }

    private func generateParticles(in size: CGSize) {
        guard particleSeeds.isEmpty else { return }

        var seeds: [ParticleSeed] = []

        for i in 0 ..< particleCount {
            // 在视图范围内随机生成粒子起始位置
            let startX = CGFloat.random(in: 0 ... size.width)
            let startY = CGFloat.random(in: 0 ... size.height)

            // 粒子移动方向：朝向黑洞（圆心），带有一些随机偏移
            let baseAngle = blackHoleDirection + Double.random(in: -0.5 ... 0.5)

            // 随机速度和延迟
            let speed = CGFloat.random(in: 0.5 ... 1.5)
            let delay = Double.random(in: 0 ... 0.3)
            let particleSize = CGFloat.random(in: 2 ... 6)

            seeds.append(ParticleSeed(
                id: i,
                startX: startX,
                startY: startY,
                angle: baseAngle,
                speed: speed,
                delay: delay,
                size: particleSize
            ))
        }

        particleSeeds = seeds
    }
}

extension View {
    /// 应用像素化消散效果
    /// - Parameters:
    ///   - progress: 消散进度 (0-1)
    ///   - blackHoleDirection: 黑洞方向（弧度）
    func pixelDissolve(progress: Double, blackHoleDirection: Double = .pi / 2) -> some View {
        modifier(PixelDissolveModifier(progress: progress, blackHoleDirection: blackHoleDirection))
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var progress: Double = 0

        var body: some View {
            VStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue)
                    .frame(width: 100, height: 120)
                    .pixelDissolve(progress: progress)

                Slider(value: $progress, in: 0 ... 1)
                    .padding()

                Button("Animate") {
                    progress = 0
                    withAnimation(.easeInOut(duration: 0.8)) {
                        progress = 1
                    }
                }
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
