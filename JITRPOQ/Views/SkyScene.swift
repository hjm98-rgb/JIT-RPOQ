//
//  SkyScene.swift
//  JIT RPOQ
//
//  写实天空：真实摄影云层 + 缓慢推移 + 分层视差。
//  所有位移都用连续时间计算，避免任何跳变。
//

import SwiftUI

enum SkyMood: String, CaseIterable {
    case day
    case dusk
    case night

    var imageName: String {
        switch self {
        case .day: return "SkyDay"
        case .dusk: return "SkyDusk"
        case .night: return "SkyNight"
        }
    }

    /// 顶部到中部的染色，让不同场景有各自的时间感
    var topTint: Color {
        switch self {
        case .day: return Color(red: 0.10, green: 0.36, blue: 0.68)
        case .dusk: return Color(red: 0.42, green: 0.24, blue: 0.42)
        case .night: return Color(red: 0.04, green: 0.06, blue: 0.16)
        }
    }

    var bottomTint: Color {
        switch self {
        case .day: return Color(red: 0.72, green: 0.86, blue: 0.96)
        case .dusk: return Color(red: 0.98, green: 0.66, blue: 0.42)
        case .night: return Color(red: 0.10, green: 0.10, blue: 0.22)
        }
    }

    var cloudTint: Color {
        switch self {
        case .day: return .white
        case .dusk: return Color(red: 1.0, green: 0.86, blue: 0.72)
        case .night: return Color(red: 0.62, green: 0.70, blue: 0.92)
        }
    }

    var cloudOpacity: Double {
        switch self {
        case .day: return 0.88
        case .dusk: return 0.72
        case .night: return 0.34
        }
    }

    /// 光晕（白昼是太阳的方向感，黄昏是落日余晖，夜晚是月亮的冷光）
    var glowColor: Color {
        switch self {
        case .day: return Color(red: 1.0, green: 0.98, blue: 0.88)
        case .dusk: return Color(red: 1.0, green: 0.72, blue: 0.40)
        case .night: return Color(red: 0.72, green: 0.80, blue: 1.0)
        }
    }

    var glowOpacity: Double {
        switch self {
        case .day: return 0.55
        case .dusk: return 0.60
        case .night: return 0.22
        }
    }

    var textPrimary: Color {
        switch self {
        case .day: return Color(white: 1.0)
        case .dusk: return Color(red: 1.0, green: 0.96, blue: 0.92)
        case .night: return Color(red: 0.92, green: 0.95, blue: 1.0)
        }
    }

    var textSecondary: Color {
        switch self {
        case .day: return Color(white: 1.0, opacity: 0.76)
        case .dusk: return Color(red: 1.0, green: 0.93, blue: 0.86, opacity: 0.78)
        case .night: return Color(red: 0.82, green: 0.88, blue: 1.0, opacity: 0.74)
        }
    }
}

/// 全屏天空。fall: 0 静止，1 表示急速下坠到底（切页瞬间用）。
struct SkyBackground: View {
    var mood: SkyMood
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
                    cloudField(w: w, h: h, t: t)
                    colorGrade(w: w, h: h)
                    sunlight(w: w, h: h)
                    if fall > 0.72 {
                        Color.white.opacity((fall - 0.72) / 0.28 * 0.55)
                            .blendMode(.plusLighter)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .scaleEffect(1 + fall * 0.65, anchor: .center)
                .offset(y: fall * h * 1.05)
                .blur(radius: fall * 9)
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
    }

    private func baseImage(w: CGFloat, h: CGFloat, t: Double) -> some View {
        Image(mood.imageName)
            .resizable()
            .scaledToFill()
            .frame(width: w * 1.12, height: h * 1.12)
            .scaleEffect(1.04 + 0.035 * sin(t / 34.0))
            .offset(x: CGFloat(sin(t / 46.0)) * w * 0.018,
                    y: CGFloat(cos(t / 58.0)) * h * 0.014)
            .position(x: w / 2, y: h / 2)
    }

    /// 多层云：越靠下越大越慢，形成真实视差
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
                    .colorMultiply(mood.cloudTint)
                    .opacity(mood.cloudOpacity * (1.0 - 0.16 * index))
                    .blur(radius: CGFloat(index) * 0.9)
                    .position(x: x, y: y)
            }
        }
    }

    private func colorGrade(w: CGFloat, h: CGFloat) -> some View {
        LinearGradient(
            colors: [mood.topTint.opacity(0.34), Color.clear, mood.bottomTint.opacity(0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: w, height: h)
        .blendMode(.softLight)
    }

    private func sunlight(w: CGFloat, h: CGFloat) -> some View {
        RadialGradient(
            colors: [mood.glowColor.opacity(mood.glowOpacity), Color.clear],
            center: UnitPoint(x: 0.82, y: 0.16),
            startRadius: 0,
            endRadius: max(w, h) * 0.62
        )
        .frame(width: w, height: h)
        .blendMode(.screen)
    }
}

/// 覆盖在天空上的玻璃面，统一质感
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
