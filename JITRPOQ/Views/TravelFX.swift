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

    private let lineCount = 34

    var body: some View {
        Canvas { context, size in
            guard progress > 0.12 else { return }
            let strength = opacity(for: progress)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = hypot(size.width, size.height) * 0.75
            var rng = SeededGenerator(seed: 20261115)

            for index in 0..<lineCount {
                let angle = Double(index) / Double(lineCount) * 2 * .pi + rng.next() * 0.12
                let inner = maxRadius * (0.10 + rng.next() * 0.22)
                let outer = maxRadius * (0.75 + rng.next() * 0.55) * (0.55 + progress * 0.75)
                guard outer > inner else { continue }

                let start = CGPoint(x: center.x + cos(angle) * inner,
                                    y: center.y + sin(angle) * inner)
                let end = CGPoint(x: center.x + cos(angle) * outer,
                                  y: center.y + sin(angle) * outer)

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                let width = 0.5 + rng.next() * 1.4
                context.stroke(
                    path,
                    with: .color(.white.opacity(strength * (0.25 + rng.next() * 0.55))),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func opacity(for progress: Double) -> Double {
        if progress < 0.35 { return (progress - 0.12) / 0.23 * 0.5 }
        if progress < 0.78 { return 0.5 + (progress - 0.35) / 0.43 * 0.45 }
        return max(0, 1 - (progress - 0.78) / 0.22)
    }
}

struct TravelOverlay: View {
    var progress: Double
    var flash: Double

    var body: some View {
        ZStack {
            SpeedLines(progress: progress)
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.55 * min(progress * 1.4, 1))],
                center: .center,
                startRadius: 0,
                endRadius: 700
            )
            .allowsHitTesting(false)
            Color.white.opacity(flash).blendMode(.plusLighter).allowsHitTesting(false)
        }
        .ignoresSafeArea()
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
