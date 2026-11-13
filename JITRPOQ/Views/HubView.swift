//
//  HubView.swift
//  JIT RPOQ
//
//  新版首页：写实天空 + 悬浮状态 + 总库入口。
//

import SwiftUI

struct HubView: View {
    @EnvironmentObject var model: AppModel

    var onEnterLab: () -> Void
    var onSettings: () -> Void
    var onRepo: () -> Void

    private var t: (String) -> String {
        { L10n.t($0, model.language) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                statusPanel
                Spacer(minLength: 18)
                hubButton
                Spacer(minLength: 22)
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("hub.wordmark"))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(SkyMood.day.textSecondary)
                Text(t("hub.headline"))
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(SkyMood.day.textPrimary)
            }
            Spacer()
            GlassCircleButton(systemImage: "gearshape", action: onSettings)
        }
        .padding(.top, 4)
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .fill(model.vpnConnected ? Color(red: 0.36, green: 0.90, blue: 0.66) : Color(red: 1.0, green: 0.52, blue: 0.42))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 0.6)
                            .frame(width: 9, height: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.vpnConnected ? t("hub.vpnOn") : t("hub.vpnOff"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SkyMood.day.textPrimary)
                    Text(model.vpnConnected ? t("hub.vpnOnDetail") : t("hub.vpnOffDetail"))
                        .font(.system(size: 12))
                        .foregroundStyle(SkyMood.day.textSecondary)
                }

                Spacer(minLength: 8)

                if !model.vpnConnected {
                    Button(action: { model.openLocalDevVPN() }) {
                        Text(t("hub.enableVPN"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 0.8)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Image(systemName: "doc.badge.key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SkyMood.day.textSecondary)
                Text(t("hub.pairing"))
                    .font(.system(size: 13))
                    .foregroundStyle(SkyMood.day.textSecondary)
                Spacer()
                Text(model.pairingExists ? t("hub.pairingReady") : t("hub.pairingMissing"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.pairingExists
                                     ? Color(red: 0.60, green: 0.95, blue: 0.78)
                                     : Color(red: 1.0, green: 0.76, blue: 0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
    }

    private var hubButton: some View {
        Button(action: onEnterLab) {
            VStack(spacing: 12) {
                ZStack {
                    ForEach(0..<2, id: \.self) { ring in
                        Circle()
                            .stroke(Color.white.opacity(ring == 0 ? 0.34 : 0.16), lineWidth: ring == 0 ? 1.2 : 0.8)
                            .frame(width: ring == 0 ? 92 : 116, height: ring == 0 ? 92 : 116)
                    }
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.55), radius: 10, y: 3)
                }
                .frame(height: 120)

                Text(t("hub.hub"))
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.5), radius: 12, y: 3)

                Text(t("hub.hubHint"))
                    .font(.system(size: 12))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                , in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 24, y: 10)
        }
        .buttonStyle(HubPressStyle())
    }

    private var footer: some View {
        Button(action: onRepo) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(t("hub.repo"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(SkyMood.day.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HubPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
