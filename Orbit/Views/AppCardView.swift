//
//  AppCardView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/7/26.
//

import SwiftUI

/// 弧顶梯形形状 - 严格同心圆扇形，保证平滑曲线
struct ArcTrapezoidShape: Shape {
    /// 左右边倾斜角度（亦即扇形的张角的一半）
    let slantAngle: Double
    /// 圆角半径
    let cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height
        
        // 1. 计算几何参数
        // 假设左右边通过延长线交于一点（圆心），该点位于卡片下方
        // 倾斜角 theta 即为圆心角的一半
        let theta = slantAngle * .pi / 180
        
        // 计算外圆半径 (Outer Radius)
        // 几何关系：tan(theta) = (width / 2) / (Radius_apex)
        // 圆心到顶部直线的垂直距离
        let radiusToTopLine = (width / 2) / tan(theta)
        
        // 圆心坐标 (在 rect 坐标系中)
        // x: 居中
        // y: radiusToTopLine (因为 rect.minY = 0, y 向下增加)
        let center = CGPoint(x: width / 2, y: radiusToTopLine)
        
        // 外圆半径 (Top corners to Center)
        let outerRadius = sqrt(pow(width / 2, 2) + pow(radiusToTopLine, 2))
        
        // 内圆半径 (Bottom corners to Center)
        // 假设侧边是径向的，那么高度直接减去即可吗？
        // 不完全是，rect.height 是垂直高度。
        // 还是通过底部宽度计算？
        // 我们希望底部贴合 rect.maxY.
        // 底部中心点距离圆心：radiusToTopLine - height
        // 所以内圆半径是 radiusToTopLine - height (这是最短距离，即垂直距离)
        // 但我们要的是弧线半径。
        // 如果内弧顶点的 y = height，那么内弧半径 = radiusToTopLine - height.
        // 半径 R_in = radiusToTopLine - height
        let innerRadius = radiusToTopLine - height
        
        // 校验：防止半径过小
        if innerRadius < cornerRadius {
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        }
        
        // 2. 角度参数 (SwiftUI Path 坐标系: 0是右, 90是下, 180是左, 270是上)
        // 我们的圆心在下方，Top弧在上方。
        // 实际上圆心在 (Width/2, LargeY).
        // 顶部弧线对应角度范围：270 +/- theta
        // 但是，我们的圆心是计算出来的虚拟几何中心。
        
        // 让我们修正圆心位置的理解：
        // 顶部两角是 (0,0) 和 (Width,0).
        // 它们必须在圆上。由于圆心在 x=Width/2 轴上。
        // 设圆心为 (Width/2, Cy).
        // R^2 = (W/2)^2 + Cy^2.
        // 同时侧边角度是 slantAngle.
        // 侧边是径向线。
        // (0,0) 到 (Width/2, Cy) 的向量角度应当对应 slantAngle.
        // 向量 V = ( -W/2, -Cy ).
        // tan(angle_vertical) = (W/2) / Cy = tan(theta).
        // 所以 Cy = (W/2) / tan(theta).
        // 这与上面计算一致。
        
        // 角度约定：
        // 垂直向上是 270度 (-pi/2)
        // 左边界角度：270 - theta的角度值
        // 右边界角度：270 + theta的角度值
        let startAngleDeg = 270 - slantAngle
        let endAngleDeg = 270 + slantAngle
        
        // 3. 构建带圆角的扇形路径
        // 我们不能直接画四条线，要计算圆角内缩
        
        // 辅助函数：将极坐标转换为点
        func point(angleDeg: Double, radius: CGFloat) -> CGPoint {
            let angleRad = angleDeg * .pi / 180
            return CGPoint(
                x: center.x + radius * CGFloat(cos(angleRad)),
                y: center.y + radius * CGFloat(sin(angleRad))
            )
        }
        
        // 修正：我们要画的是"上面"的扇形区块。
        // 圆心在下方？不，按上面的计算，Cy 是正数 (radiusToTopLine).
        // Rect (0,0) 在上方。Cy 很大，说明圆心在很下面。
        // 那么 (0,0) 相对于圆心是 ( -W/2, -Cy ). 都在上方 (负Y方向相对圆心)。
        // 等等，rect坐标系 y向下。
        // 圆心 (W/2, Cy). (0,0) 在圆心上方 Cy 处?
        // 0 < Cy. 所以 (0,0) 在圆心上方.
        // 我们的弧线是凸向上的 (y < Cy).
        // 所以半径是 OuterRadius.
        // 角度确实是 270 (向上).
        
        // --- 圆角处理 ---
        // 我们有4个角。每个角有一个圆角圆心。
        // 几何推导：
        // 它是扇形往里缩 r.
        // 角半角 alpha = theta.
        // 外圆角圆心半径 R_oc = OuterRadius - r
        // 内圆角圆心半径 R_ic = InnerRadius + r
        // 角度偏移: beta = asin(r / R_center)
        
        let r = cornerRadius
        let R_oc = outerRadius - r
        let R_ic = innerRadius + r
        
        let beta_outer = asin(r / R_oc) * 180 / .pi
        let beta_inner = asin(r / R_ic) * 180 / .pi
        
        // 4个圆弧段
        // 1. 顶部弧线 (Outer Arc)
        // 范围：[start + beta, end - beta]
        // 方向：顺时针 (angle增加)
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startAngleDeg + beta_outer),
            endAngle: .degrees(endAngleDeg - beta_outer),
            clockwise: false // false implies increasing angle (visually clockwise in Y-down?) 
                             // Wait, 270-10 -> 270+10 is Left to Right.
                             // Left to Right is Clockwise visual?
                             // 12 o'clock -> 1 o'clock. Yes.
                             // But SwiftUI clockwise: false means standard counter-clockwise (increasing radians)?
                             // Yes. Standard trig: 0->90 is increasing.
                             // So false means increasing angle.
                             // So start(260) -> end(280) with clockwise: false.
        )
        
        // 2. 右上圆角
        // 圆心：point(endAngle - beta, R_oc)
        // 这是一个小圆弧，连接 OuterArc 和 RightLine
        // 起始角度：endAngle - beta (即 OuterArc切线法向) -> 实际上是径向角度
        // 结束角度：endAngle + 90?
        // 此时不仅位置要对，切线也要对。
        // 圆角圆心在 (270+theta-beta, R_oc).
        // 它的角度是 (270+theta-beta).
        // 我们的当前点在 外圆上。
        // 右上角圆弧中心:
        let trCenter = point(angleDeg: endAngleDeg - beta_outer, radius: R_oc)
        // 绘制圆角：从 (OuterArc接点) 到 (RightLine接点)
        // 接点角度(相对于小圆心):
        // OuterArc接点: 径向向外 -> -90度相对径向? 不，是径向本身。
        // 准确说是：我们从小圆心的 "上方"(背离大圆心方向) 开始。
        // 大圆圆心在 C. 小圆圆心在 P.
        // 接点 T1 在 C->P 的延长线上。
        // 所以 T1 相对于 P 的角度，就是 P 相对于 C 的角度。即 (endAngle - beta).
        // 结束点 T2: 垂直于侧边。侧边角度 (endAngle).
        // T2 相对于 P 的角度：endAngle + 90.
        path.addArc(
            center: trCenter,
            radius: r,
            startAngle: .degrees(endAngleDeg - beta_outer),
            endAngle: .degrees(endAngleDeg + 90),
            clockwise: false // Increasing angle?
                             // 280 -> 370. Yes.
        )
        
        // 3. 右边线 (实际上是隐式的，因为我们直接画内圆角)
        // 但我们需要画到右下角圆角的起点。
        // 右下圆角圆心
        let brCenter = point(angleDeg: endAngleDeg - beta_inner, radius: R_ic)
        // 右边线即两圆角切点连线
        
        // 4. 右下圆角
        // 起始：垂直于侧边 -> endAngle + 90.
        // 结束：径向向内 -> endAngle - beta_inner?
        // 不，内圆角。内圆是空心的。
        // 圆角圆心在 R_ic. 大圆在 R_inner.
        // 切点在大圆和小圆之间? 不，小圆在大圆"外侧"(实体侧)。
        // 实体是在 R > R_inner.
        // 所以小圆心在 R_ic = R_inner + r.
        // 切点 T_in 在 C -> P_br 连线上，且在 P_br 内侧。
        // 即 T_in = P_br - r * u_vec.
        // 也就是 T_in 离 C 的距离是 R_ic - r = R_inner.
        // 所以 T_in 相对于 P_br 的角度，是 (P_br 相对于 C 的角度) + 180度.
        // 即 (endAngle - beta_inner) + 180.
        path.addArc(
            center: brCenter,
            radius: r,
            startAngle: .degrees(endAngleDeg + 90),
            endAngle: .degrees(endAngleDeg - beta_inner + 180),
            clockwise: false
        )
        
        // 5. 底部弧线 (Inner Arc)
        // 范围：[end - beta + 180, start + beta + 180]?
        // 不，我们是沿着 InnerRadius 画。
        // Inner radius 对应的是 (end - beta) 到 (start + beta) 的角度范围。
        // 但方向是 从右到左 (decreasing angle).
        // 所以 clockwise: true.
        // 角度值还是原始的大圆角度。
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(endAngleDeg - beta_inner),
            endAngle: .degrees(startAngleDeg + beta_inner),
            clockwise: true // Decreasing angle (Right to Left)
        )
        
        // 6. 左下圆角
        let blCenter = point(angleDeg: startAngleDeg + beta_inner, radius: R_ic)
        // 起始：(start + beta) + 180?
        // 左侧是 startAngle (e.g. 260).
        // 径向角度 start + beta.
        // 切点在内侧 -> +180.
        // 结束：垂直于侧边. 侧边角度 startAngle.
        // 左侧边法向?
        // 侧边向外是 startAngle. 向内是 startAngle + 180.
        // 垂直? startAngle - 90.
        path.addArc(
            center: blCenter,
            radius: r,
            startAngle: .degrees(startAngleDeg + beta_inner + 180),
            endAngle: .degrees(startAngleDeg - 90),
            clockwise: false
        )
        
        // 7. 左上圆角
        let tlCenter = point(angleDeg: startAngleDeg + beta_outer, radius: R_oc)
        // 起始：startAngle - 90.
        // 结束：startAngle + beta [即径向向外]
        path.addArc(
            center: tlCenter,
            radius: r,
            startAngle: .degrees(startAngleDeg - 90),
            endAngle: .degrees(startAngleDeg + beta_outer),
            clockwise: false
        )
        
        path.closeSubpath()
        return path
    }
}

/// 单个应用卡片 - 弧顶梯形
struct AppCardView: View {
    let app: AppInfo
    let index: Int
    let isSelected: Bool
    let animationProgress: Double
    let rotation: Double
    let orbitAngle: Double

    @Binding var dragState: CardDragState
    let dissolveProgress: Double
    let originalPosition: CGPoint
    let windowCenter: CGPoint
    let windowBounds: CGRect
    let dragCoordinateSpaceName: String

    private var cardSize: CardSize { OrbitConfig.cardSize }
    private var contentRotation: Double {
        guard OrbitConfig.lockRingItemsUpright else { return 0 }
        return -(orbitAngle + rotation)
    }
    private var letterYOffset: CGFloat {
        guard OrbitConfig.lockRingItemsUpright else { return 0 }
        switch cardSize {
        case .small:
            return 4
        case .medium:
            return 6
        case .large:
            return 8
        case .extraLarge:
            return 9
        }
    }
    private var usesLiquidGlass: Bool {
        guard OrbitConfig.cardMaterial == .liquidGlass else { return false }
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    var body: some View {
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
            dropActivationRadius: OrbitConfig.blackHoleActivationRadius,
            usesLiquidGlass: usesLiquidGlass
        ) {
            VStack(spacing: 4) {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: cardSize.iconSize, height: cardSize.iconSize)
                    .rotationEffect(.degrees(contentRotation))

                if let letter = app.firstLetter {
                    Text(String(letter))
                        .font(.system(size: cardSize.letterFontSize, weight: .semibold))
                        .foregroundColor(Color(white: 0.5))
                        .rotationEffect(.degrees(contentRotation))
                        .offset(y: letterYOffset)
                }
            }
            .offset(x: cardSize.iconOffsetX, y: cardSize.iconOffsetY)
        }
    }
}

/// C形环布局 - 第一个在正上方，支持扇形展开动画（沿圆弧路径）
struct ArcLayout {
    let index: Int
    let totalCount: Int
    let selectedIndex: Int
    /// 动画进度 0-1，用于扇形展开
    let animationProgress: Double
    /// 半径（根据弧长动态调整，避免首尾重叠）
    let radius: CGFloat
    /// 当前轨道角度（卡片绕中心旋转的角度，用于 rotationEffect）
    /// 从 0（正上方）平滑过渡到最终位置
    let orbitAngle: Double
    /// 卡片自身的旋转角度
    /// 需要抵消外层 rotationEffect 带来的旋转，保持原来的扇形朝向
    let cardRotation: Double
    /// Z轴层级 - 像楼梯一样，后面的在上面
    let zIndex: Double

    init(index: Int, totalCount: Int, selectedIndex: Int, animationProgress: Double) {
        self.index = index
        self.totalCount = totalCount
        self.selectedIndex = selectedIndex
        self.animationProgress = animationProgress

        let anglePerCard = Self.anglePerCard(for: totalCount)
        let totalArc = Double(max(totalCount - 1, 0)) * anglePerCard
        let baseRadius = OrbitConfig.cardSize.orbitRadius

        // 当弧长超过270度时，开始增大半径
        let thresholdArc: Double = 270
        if totalArc <= thresholdArc {
            radius = baseRadius
        } else {
            // 超出部分按比例增大半径
            let scale = totalArc / thresholdArc
            radius = baseRadius * CGFloat(scale)
        }

        let finalOrbitAngle: Double
        if totalCount > 1 {
            let step = totalArc / Double(totalCount - 1)
            finalOrbitAngle = step * Double(index)
        } else {
            finalOrbitAngle = 0
        }

        orbitAngle = finalOrbitAngle * animationProgress
        // 外层 rotationEffect(orbitAngle) 会让卡片旋转 orbitAngle 度
        // 原来的朝向是 orbitAngle * 0.96
        // 所以这里需要：-orbitAngle + orbitAngle * 0.96 = -orbitAngle * 0.04
        cardRotation = -orbitAngle * 0.04

        if index == selectedIndex {
            zIndex = 1000
        } else {
            // 让前面的卡片压住后面的卡片
            zIndex = Double(totalCount - index)
        }
    }

    /// 计算卡片在窗口中的实际位置
    /// - Parameter center: 窗口中心点
    /// - Returns: 卡片中心的实际位置
    func cardPosition(relativeTo center: CGPoint) -> CGPoint {
        // 卡片先放在正上方（offset y: -radius），然后绕中心旋转 orbitAngle 度
        // 旋转后的位置计算：
        // x = center.x + radius * sin(orbitAngle)
        // y = center.y - radius * cos(orbitAngle)
        let angleInRadians = orbitAngle * .pi / 180
        let x = center.x + radius * CGFloat(sin(angleInRadians))
        let y = center.y - radius * CGFloat(cos(angleInRadians))
        return CGPoint(x: x, y: y)
    }

    /// 根据应用数量计算需要的窗口大小
    static func windowSize(forAppCount count: Int) -> CGFloat {
        let anglePerCard = anglePerCard(for: count)
        let totalArc = Double(max(count - 1, 0)) * anglePerCard
        let baseRadius = OrbitConfig.cardSize.orbitRadius
        let cardHeight = OrbitConfig.cardSize.cardHeight

        let thresholdArc: Double = 270
        let radius: CGFloat
        if totalArc <= thresholdArc {
            radius = baseRadius
        } else {
            let scale = totalArc / thresholdArc
            radius = baseRadius * CGFloat(scale)
        }

        // 窗口大小 = 半径 * 2 + 卡片高度 + 边距
        return (radius + cardHeight) * 2 + 50
    }

    private static func anglePerCard(for count: Int) -> Double {
        if count <= 6 {
            return 30
        } else if count <= 8 {
            return 28
        } else {
            return 26
        }
    }
}
