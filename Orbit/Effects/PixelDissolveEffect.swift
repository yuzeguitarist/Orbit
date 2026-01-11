//
//  PixelDissolveEffect.swift
//  Orbit
//
//  Created by Claude on 1/8/26.
//

import Combine
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

    func body(content: Content) -> some View {
        content
            .opacity(progress < 0.1 ? 1 : max(0, 1 - progress * 1.2))
// 粒子特效在背景中显示，避免遮挡卡片内容
            .background(
                GeometryReader { geo in
                    Canvas { context, size in
                        guard progress > 0.05 else { return }

                        for seed in particleSeeds {
                            // 计算粒子当前位置
                            let adjustedProgress = max(0, (progress - seed.delay) / (1 - seed.delay))
                            guard adjustedProgress > 0 else { continue }

                            // 粒子向黑洞方向移动
                            let moveDistance = seed.speed * CGFloat(adjustedProgress) * 100
                            let currentX = seed.startX + cos(seed.angle) * moveDistance
                            let currentY = seed.startY + sin(seed.angle) * moveDistance

                            // 粒子透明度随进度降低
                            let alpha = max(0, 1 - adjustedProgress * 1.5)

                            // 粒子大小随进度缩小
                            let currentSize = seed.size * CGFloat(1 - adjustedProgress * 0.5)

                            // 绘制粒子
                            let rect = CGRect(
                                x: currentX - currentSize / 2,
                                y: currentY - currentSize / 2,
                                width: currentSize,
                                height: currentSize
                            )

                            context.opacity = alpha
                            // 使用金橙色粒子
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

/// 消散动画控制器
class DissolveAnimationController: ObservableObject {
    @Published var progress: Double = 0

    private var displayLink: CVDisplayLink?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = OrbitConfig.dissolveDuration

    func startDissolve(duration: TimeInterval = OrbitConfig.dissolveDuration, completion: @escaping () -> Void) {
        self.duration = duration
        progress = 0

        // 使用 Timer 实现动画（SwiftUI 友好）
        let startTime = CACurrentMediaTime()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let newProgress = min(1.0, elapsed / self.duration)

            DispatchQueue.main.async {
                self.progress = newProgress
            }

            if newProgress >= 1.0 {
                timer.invalidate()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    func reset() {
        progress = 0
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
