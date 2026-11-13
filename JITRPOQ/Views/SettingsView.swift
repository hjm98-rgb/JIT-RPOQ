//
//  SettingsView.swift
//  JIT RPOQ
//
//  夜色天空下的设置页：语言、天空动画、自动探测、缓存与关于。
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var onClose: () -> Void

    private func t(_ key: String) -> String {
        L10n.t(key, model.language)
    }

    var body: some View {
        ZStack {
            SkyBackground(mood: .night)
            Color.black.opacity(0.42).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    languageCard
                    behaviourCard
                    aboutCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(t("settings.title"))
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(SkyMood.night.textPrimary)
            Spacer()
            GlassCircleButton(systemImage: "xmark", size: 40, action: onClose)
        }
        .padding(.bottom, 2)
    }

    private var languageCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(t("settings.language"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(t("settings.languageDetail"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.66))
                }
                HStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                model.language = lang.rawValue
                            }
                        } label: {
                            Text(lang.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Color.white.opacity(model.language == lang.rawValue ? 0.22 : 0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(Color.white.opacity(model.language == lang.rawValue ? 0.34 : 0.12), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var behaviourCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                toggleRow(t("settings.sky"), detail: t("settings.skyDetail"), binding: $model.skyAnimation)

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.7)

                Button {
                    model.clearIconCache()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("settings.cache"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                            Text(t("settings.cacheDetail"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.66))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.7)

                Button {
                    model.probeVPN()
                    model.refreshPairingState()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("common.retry"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                            Text(model.vpnConnected ? t("hub.vpnOn") : t("hub.vpnOff"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleRow(_ title: String, detail: String, binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(Color(red: 0.42, green: 0.86, blue: 0.92))
        }
    }

    private var aboutCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("JIT RPOQ")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(t("settings.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.66))
                }

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.7)

                HStack {
                    Text(t("settings.license"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.66))
                    Spacer()
                    Text("MIT")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }

                Button {
                    model.openRepository()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("settings.repo"))
                                .font(.system(size: 13, weight: .medium))
                            Text(t("settings.repoDetail"))
                                .font(.system(size: 10.5))
                                .opacity(0.7)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
