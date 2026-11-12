//
//  RootView.swift
//  JIT RPOQ
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: Tab = .home

    enum Tab: Hashable {
        case home, apps, scripts, logs
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("主页", systemImage: "bolt.fill") }
                .tag(Tab.home)

            AppsView()
                .tabItem { Label("应用", systemImage: "square.grid.2x2") }
                .tag(Tab.apps)

            ScriptsView()
                .tabItem { Label("脚本", systemImage: "curlybraces") }
                .tag(Tab.scripts)

            LogView()
                .tabItem { Label("日志", systemImage: "text.alignleft") }
                .tag(Tab.logs)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .alert("出错了", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("知道了", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.cardAlt)
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())
                    .padding(.bottom, 72)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { model.toast = nil }
                        }
                    }
            }
        }
        .onChange(of: model.apps.count) { _, _ in
            model.consumePendingAuto()
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
