//
//  RootView.swift
//  JIT RPOQ
//
//  新版外壳：天空 → 总库 →（急速下坠）→ JIT 实验室。
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage = .hub
    @State private var fall: Double = 0
    @State private var showSettings = false
    @State private var isFalling = false
    @State private var flash: Double = 0
    @State private var impactScale: CGFloat = 1.0

    enum Stage {
        case hub
        case lab
    }

    private var mood: SceneKind {
        stage == .hub ? .day : .descent
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: mood, animated: model.skyAnimation, fall: fall)

            Color.black.opacity(stage == .hub ? 0.08 : 0.16)
                .ignoresSafeArea()

            Group {
                if stage == .hub {
                    HubView(
                        onEnterLab: enterLab,
                        onSettings: { showSettings = true },
                        onRepo: { model.openRepository() }
                    )
                    .transition(.opacity)
                } else {
                    JITLabView(
                        onBack: leaveLab,
                        onSettings: { showSettings = true },
                        onRepo: { model.openRepository() }
                    )
                    .transition(.opacity)
                }
            }
            .scaleEffect(impactScale)
            .opacity(1 - min(fall * 1.7, 1))
            .scaleEffect(1 - min(fall, 1) * 0.06)

            TravelOverlay(progress: fall, flash: flash)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false })
                .environmentObject(model)
        }
        .alert(alertTitle, isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button(alertOK, role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.8))
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation { model.toast = nil }
                    }
            }
        }
        .onChange(of: model.homeRequest) { _, _ in
            withAnimation(.easeOut(duration: 0.3)) { stage = .hub }
        }
        .onChange(of: model.apps.count) { _, _ in
            model.consumePendingAuto()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.probeVPN() }
        }
    }

    private var alertTitle: String {
        model.language == "en" ? "Something went wrong" : "出错了"
    }

    private var alertOK: String {
        model.language == "en" ? "OK" : "知道了"
    }

    /// 总库 → 天空急速下坠 → 实验室
    private func enterLab() {
        guard !isFalling else { return }
        isFalling = true
        fall = 0
        flash = 0
        impactScale = 1.0
        SoundPlayer.shared.startFall()

        // 先慢后快：0.55 之前几乎悬停，之后加速俯冲
        withAnimation(.timingCurve(0.58, 0.0, 0.88, 1.0, duration: 1.55)) {
            fall = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.16) {
            SoundPlayer.shared.land()
            withAnimation(.easeOut(duration: 0.10)) { flash = 0.72 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.42) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                stage = .lab
                fall = 0
                impactScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.30)) { flash = 0 }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { impactScale = 1.0 }
            isFalling = false
        }
    }

    private func leaveLab() {
        withAnimation(.easeOut(duration: 0.35)) {
            stage = .hub
        }
    }
}

@main
struct JITRPOQApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.handleURL(url)
                }
        }
    }
}
