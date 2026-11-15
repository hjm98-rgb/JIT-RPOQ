//
//  TravelFX.swift
//  JIT RPOQ
//
//  坠落转场的视觉层：径向速度线、白光、暗角、落地抖动。
//  progress 0 → 1 随天空坠落推进，速度线在中后段最强。
//

import SwiftUI

struct SpeedLines: View {
    var progress: Double

    private struct Streak {
        var angle: Double
        var inner: Double
        var outer: Double
        var width: Double
        var alpha: Double
    }

    var body: some View {
        Canvas { context, size in
            guard progress > 0.12 else { return }
            let specs = streaks()
            let midX = size.width / 2
            let midY = size.height / 2
            let radius = hypot(size.width, size.height) * 0.78
            for spec in specs {
                let startX = midX + CGFloat(cos(spec.angle)) * CGFloat(spec.inner * Double(radius))
                let startY = midY + CGFloat(sin(spec.angle)) * CGFloat(spec.inner * Double(radius))
                let endX = midX + CGFloat(cos(spec.angle)) * CGFloat(spec.outer * Double(radius))
                let endY = midY + CGFloat(sin(spec.angle)) * CGFloat(spec.outer * Double(radius))
                var path = Path()
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
                let color = Color.white.opacity(spec.alpha)
                context.stroke(path, with: .color(color), lineWidth: spec.width)
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func streaks() -> [Streak] {
        var rng = SeededGenerator(seed: 20261115)
        let strength = strengthValue()
        let count = 34
        var result: [Streak] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let angle: Double = Double(index) / Double(count) * 2 * .pi + rng.next() * 0.12
            let inner: Double = 0.10 + rng.next() * 0.22
            let spread: Double = 0.75 + rng.next() * 0.55
            let factor: Double = 0.55 + progress * 0.75
            let width: Double = 0.5 + rng.next() * 1.4
            let alpha: Double = strength * (0.25 + rng.next() * 0.55)
            result.append(Streak(angle: angle, inner: inner, outer: spread * factor, width: width, alpha: alpha))
        }
        return result
    }

    private func strengthValue() -> Double {
        if progress < 0.35 { return (progress - 0.12) / 0.23 * 0.5 }
        if progress < 0.78 { return 0.5 + (progress - 0.35) / 0.43 * 0.45 }
        return max(0, 1 - (progress - 0.78) / 0.22)
    }
}

struct TravelOverlay: View {
    var progress: Double
    var flash: Double
    /// 落点场景图：坠落途中从画面下方升起，最后占满整屏，取代黑屏
    var previewImage: String? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if let name = previewImage {
                    landingPreview(name: name, w: w, h: h)
                }
                SpeedLines(progress: progress)
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.30 * min(progress * 1.2, 1))],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.9
                )
                .allowsHitTesting(false)
                Color.white.opacity(flash).blendMode(.plusLighter).allowsHitTesting(false)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func landingPreview(name: String, w: CGFloat, h: CGFloat) -> some View {
        let appear = min(max((progress - 0.10) / 0.90, 0), 1)
        let eased = 1 - pow(1 - appear, 2.0)

        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: w, height: h)
            .clipped()
            .scaleEffect(1.16 - 0.16 * CGFloat(eased))
            .offset(y: CGFloat(1 - eased) * h * 0.55)
            .blur(radius: CGFloat(1 - eased) * 8)
            .opacity(appear)
            .allowsHitTesting(false)
    }
}

/// 落地后的轻微回弹 + 抖动
struct LandingEffect: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(trigger ? 1.0 : 1.045)
            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: trigger)
    }
}

/// 稳定伪随机：每帧重算也得到同一组基准值，粒子不会闪
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) & 0xFFFF) / Double(0xFFFF)
    }
}
