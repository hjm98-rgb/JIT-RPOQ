//
//  SkyScene.swift
//  JIT RPOQ
//
//  每个页面一套独立场景：全部是真实摄影素材 + 连续时间的缓慢运镜。
//  室内走横向推移 + 光带扫过，室外走推移 + 分层云视差，保证没有一块是静态图。
//

import SwiftUI

enum SceneKind: String, CaseIterable {
    case day          // 首页：白昼天空
    case descent      // 实验室：云端俯冲
    case rooftop      // 设置：夜间天台
    case control      // 应用：控制室
    case study        // 脚本：深夜书房
    case server       // 日志：机房走廊
    case mountain     // 配对：黎明雪山
    case cloudSea     // 本机配对：云海之上

    var imageName: String {
        switch self {
        case .day: return "SkyDay"
        case .descent: return "SceneDescent"
        case .rooftop: return "SceneRooftop"
        case .control: return "SceneControl"
        case .study: return "SceneStudy"
        case .server: return "SceneServer"
        case .mountain: return "SceneMountain"
        case .cloudSea: return "SceneCloudSea"
        }
    }

    var indoor: Bool {
        switch self {
        case .control, .study, .server: return true
        default: return false
        }
    }

    var usesCloudLayer: Bool {
        switch self {
        case .day, .descent, .cloudSea: return true
        default: return false
        }
    }

    var topTint: Color {
        switch self {
        case .day: return Color(red: 0.10, green: 0.36, blue: 0.68)
        case .descent: return Color(red: 0.06, green: 0.20, blue: 0.46)
        case .rooftop: return Color(red: 0.03, green: 0.05, blue: 0.14)
        case .control: return Color(red: 0.04, green: 0.12, blue: 0.20)
        case .study: return Color(red: 0.18, green: 0.10, blue: 0.04)
        case .server: return Color(red: 0.03, green: 0.09, blue: 0.10)
        case .mountain: return Color(red: 0.24, green: 0.36, blue: 0.52)
        case .cloudSea: return Color(red: 0.10, green: 0.30, blue: 0.56)
        }
    }

    var bottomTint: Color {
        switch self {
        case .day: return Color(red: 0.72, green: 0.86, blue: 0.96)
        case .descent: return Color(red: 0.74, green: 0.84, blue: 0.94)
        case .rooftop: return Color(red: 0.10, green: 0.12, blue: 0.24)
        case .control: return Color(red: 0.06, green: 0.24, blue: 0.30)
        case .study: return Color(red: 0.36, green: 0.20, blue: 0.08)
        case .server: return Color(red: 0.05, green: 0.22, blue: 0.20)
        case .mountain: return Color(red: 0.86, green: 0.82, blue: 0.78)
        case .cloudSea: return Color(red: 0.84, green: 0.86, blue: 0.84)
        }
    }

    var glowColor: Color {
        switch self {
        case .study: return Color(red: 1.0, green: 0.74, blue: 0.40)
        case .server: return Color(red: 0.36, green: 0.92, blue: 0.86)
        case .control: return Color(red: 0.46, green: 0.80, blue: 1.0)
        case .rooftop: return Color(red: 0.60, green: 0.72, blue: 1.0)
        default: return Color(red: 1.0, green: 0.97, blue: 0.88)
        }
    }

    var glowOpacity: Double {
        switch self {
        case .study: return 0.42
        case .server: return 0.30
        case .control: return 0.38
        case .rooftop: return 0.22
        default: return 0.40
        }
    }

    var glowCenter: UnitPoint {
        switch self {
        case .study: return UnitPoint(x: 0.30, y: 0.42)
        case .server: return UnitPoint(x: 0.50, y: 0.30)
        case .control: return UnitPoint(x: 0.52, y: 0.58)
        case .rooftop: return UnitPoint(x: 0.70, y: 0.55)
        default: return UnitPoint(x: 0.82, y: 0.16)
        }
    }

    /// 文字对比度：室内偏暖白，室外纯白
    var textPrimary: Color { Color.white.opacity(0.96) }
    var textSecondary: Color {
        indoor ? Color(red: 1.0, green: 0.94, blue: 0.86, opacity: 0.72) : Color.white.opacity(0.76)
    }

    /// 压在场景上的暗化，保证玻璃面板里的字看得清
    var veil: Double {
        switch self {
        case .day: return 0.06
        case .descent: return 0.16
        case .rooftop: return 0.28
        case .control: return 0.34
        case .study: return 0.38
        case .server: return 0.34
        case .mountain: return 0.30
        case .cloudSea: return 0.24
        }
    }
}

/// 全屏场景。fall: 0 静止，1 表示急速下坠到底（切页瞬间用）。
struct SkyBackground: View {
    var kind: SceneKind
    var animated: Bool = true
    var fall: Double = 0

    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let moving = animated && !reduceMotion

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moving)) { context in
                let t = moving ? context.date.timeIntervalSince(start) : 0

                ZStack {
                    baseImage(w: w, h: h, t: t)
                    if kind == .descent || kind == .cloudSea {
                        verticalCloudBands(w: w, h: h, t: t)
                    }
                    if kind.indoor {
                        lightSweep(w: w, h: h, t: t)
                    } else if kind.usesCloudLayer {
                        cloudField(w: w, h: h, t: t)
                    }
                    AmbientParticles(kind: kind, time: t)
                        .frame(width: w, height: h)
                    colorGrade(w: w, h: h)
                    sunlight(w: w, h: h)
                    if fall > 0.80 {
                        Color.white.opacity((fall - 0.80) / 0.20 * 0.40)
                            .blendMode(.plusLighter)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .scaleEffect(1 + fall * 0.55, anchor: .center)
                .offset(y: -fall * h * 0.72)
                .blur(radius: fall * 7)
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
    }

    private func baseImage(w: CGFloat, h: CGFloat, t: Double) -> some View {
        Image(kind.imageName)
            .resizable()
            .scaledToFill()
            .frame(width: w * 1.16, height: h * 1.16)
            .scaleEffect(kind.indoor
                         ? 1.06 + 0.045 * sin(t / 40.0)
                         : 1.06 + 0.06 * sin(t / 34.0))
            .offset(x: CGFloat(sin(t / (kind.indoor ? 52.0 : 46.0))) * w * (kind.indoor ? 0.075 : 0.03),
                    y: CGFloat(cos(t / 58.0)) * h * (kind.indoor ? 0.028 : 0.022))
            .position(x: w / 2, y: h / 2)
    }

    /// 室内：一条很淡的横向光带缓慢扫过，像有光源在移动
    /// 高空俯冲：宽幅云带从下往上快速掠过，制造持续下坠的速度感
    private func verticalCloudBands(w: CGFloat, h: CGFloat, t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let index = Double(i)
                let speed = 26.0 + 14.0 * index
                let bandHeight = h * (0.42 + 0.12 * index)
                let travel = (t * speed).truncatingRemainder(dividingBy: Double(bandHeight * 1.8))
                let y = h + bandHeight - CGFloat(travel) + CGFloat(index) * h * 0.55

                Image("SkyCloud")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w * (1.5 + 0.25 * index), height: bandHeight)
                    .clipped()
                    .opacity(0.30 - 0.07 * index)
                    .blur(radius: 8 + CGFloat(index) * 4)
                    .position(x: w / 2, y: y)
            }
        }
    }

    private func lightSweep(w: CGFloat, h: CGFloat, t: Double) -> some View {
        let cycle = 26.0
        let progress = (t / cycle).truncatingRemainder(dividingBy: 1)
        let x = CGFloat(progress) * (w * 1.6) - w * 0.3
        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0), kind.glowColor.opacity(0.10), Color.white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: w * 0.42, height: h)
            .rotationEffect(.degrees(12))
            .position(x: x, y: h / 2)
            .blendMode(.plusLighter)
    }

    /// 室外：多层云，越靠下越大越慢，形成真实视差
    private func cloudField(w: CGFloat, h: CGFloat, t: Double) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let index = Double(i)
                let width = w * (1.05 + 0.30 * index)
                let cycle = 78.0 + 26.0 * index
                let phase = index / 4.4
                let progress = (t / cycle + phase).truncatingRemainder(dividingBy: 1)
                let x = CGFloat(progress) * (w * 2.4) - w * 1.15
                let y = h * (0.10 + 0.21 * index) + CGFloat(cos(t / (28.0 + 9.0 * index))) * h * 0.012

                Image("SkyCloud")
                    .resizable()
                    .scaledToFit()
                    .frame(width: width)
                    .colorMultiply(.white)
                    .opacity(0.72 - 0.14 * index)
                    .blur(radius: CGFloat(index) * 0.9)
                    .position(x: x, y: y)
            }
        }
    }

    private func colorGrade(w: CGFloat, h: CGFloat) -> some View {
        LinearGradient(
            colors: [kind.topTint.opacity(0.34), Color.clear, kind.bottomTint.opacity(0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: w, height: h)
        .blendMode(.softLight)
    }

    private func sunlight(w: CGFloat, h: CGFloat) -> some View {
        RadialGradient(
            colors: [kind.glowColor.opacity(kind.glowOpacity), Color.clear],
            center: kind.glowCenter,
            startRadius: 0,
            endRadius: max(w, h) * 0.62
        )
        .frame(width: w, height: h)
        .blendMode(.screen)
    }
}

/// 覆盖在场景上的玻璃面，统一质感
struct GlassPanel<Content: View>: View {
    var corner: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
}

/// 悬浮圆形按钮（齿轮、返回都用它，保持一致的质感）
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - 场景里的真实运动元素

/// 室内飘尘、雪山落雪、天台雨丝、高空速度条纹。
/// 全部由时间连续计算，不依赖随机每帧重建，因此不会闪。
struct AmbientParticles: View {
    let kind: SceneKind
    let time: Double

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .control, .study, .server:
                dust(in: &context, size, time)
            case .mountain:
                snow(in: &context, size, time)
            case .rooftop:
                rain(in: &context, size, time)
            case .descent, .cloudSea:
                streaks(in: &context, size, time)
            case .day:
                sparseMotes(in: &context, size, time)
            }
        }
        .allowsHitTesting(false)
    }

    private func dust(in context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        var rng = SeededGenerator(seed: 0xA11CE)
        for _ in 0..<46 {
            let baseX = rng.next() * Double(size.width)
            let baseY = rng.next() * Double(size.height)
            let speed = 2.5 + rng.next() * 7.0
            let sway = 6.0 + rng.next() * 14.0
            let radius = 0.8 + rng.next() * 1.8
            let alpha = 0.05 + rng.next() * 0.16

            let y = (baseY - t * speed).truncatingRemainder(dividingBy: Double(size.height))
            let wrappedY = y < 0 ? y + Double(size.height) : y
            let x = baseX + sin(t / 9.0 + baseY) * sway

            let rect = CGRect(x: x, y: wrappedY, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
        }
    }

    private func snow(in context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        var rng = SeededGenerator(seed: 0x5E0)
        for _ in 0..<90 {
            let baseX = rng.next() * Double(size.width)
            let baseY = rng.next() * Double(size.height)
            let speed = 14.0 + rng.next() * 34.0
            let sway = 10.0 + rng.next() * 26.0
            let radius = 1.0 + rng.next() * 2.4
            let alpha = 0.20 + rng.next() * 0.55

            let y = (baseY + t * speed).truncatingRemainder(dividingBy: Double(size.height) + 20)
            let x = baseX + sin(t / 6.0 + baseY / 30.0) * sway

            let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
        }
    }

    private func rain(in context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        var rng = SeededGenerator(seed: 0x7A11)
        for _ in 0..<70 {
            let baseX = rng.next() * Double(size.width)
            let baseY = rng.next() * Double(size.height)
            let speed = 240.0 + rng.next() * 260.0
            let length = 12.0 + rng.next() * 26.0
            let alpha = 0.06 + rng.next() * 0.16

            let y = (baseY + t * speed).truncatingRemainder(dividingBy: Double(size.height) + 60)
            let x = baseX + y * 0.18

            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + length * 0.18, y: y + length))
            context.stroke(path, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
    }

    /// 俯冲时的高速白线，越到下方越密
    private func streaks(in context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        var rng = SeededGenerator(seed: 0xDECE)
        for _ in 0..<48 {
            let baseX = rng.next() * Double(size.width)
            let baseY = rng.next() * Double(size.height)
            let speed = 400.0 + rng.next() * 520.0
            let length = 30.0 + rng.next() * 90.0
            let alpha = 0.04 + rng.next() * 0.13

            let y = (baseY + t * speed).truncatingRemainder(dividingBy: Double(size.height) + 120)
            let x = baseX + sin(baseY) * 12

            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + length))
            context.stroke(path, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }

    private func sparseMotes(in context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        var rng = SeededGenerator(seed: 0xC10D)
        for _ in 0..<26 {
            let baseX = rng.next() * Double(size.width)
            let baseY = rng.next() * Double(size.height)
            let speed = 3.0 + rng.next() * 6.0
            let radius = 0.9 + rng.next() * 1.6
            let alpha = 0.04 + rng.next() * 0.10

            let y = (baseY + t * speed).truncatingRemainder(dividingBy: Double(size.height))
            let x = baseX + sin(t / 7.0 + baseY) * 8

            let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
        }
    }
}
