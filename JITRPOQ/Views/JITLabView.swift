//
//  JITLabView.swift
//  JIT RPOQ
//
//  从天空下坠后进入的实验室：一个总入口统领所有分区。
//

import SwiftUI

struct JITLabView: View {
    @EnvironmentObject var model: AppModel

    var onBack: () -> Void
    var onSettings: () -> Void
    var onRepo: () -> Void

    @State private var path: [LabRoute] = []
    @State private var showGenerator = false

    enum LabRoute: Hashable {
        case apps
        case pairing
        case scripts
        case logs
    }

    private func t(_ key: String) -> String {
        L10n.t(key, model.language)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                SkyBackground(kind: .descent)
                Color.black.opacity(SceneKind.descent.veil).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        sectionGrid
                        generatorCard
                        repoRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
            }
            .navigationDestination(for: LabRoute.self) { route in
                switch route {
                case .apps:
                    AppsView()
                case .pairing:
                    PairingSectionView(onGenerate: { showGenerator = true })
                case .scripts:
                    ScriptsView()
                case .logs:
                    LogView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showGenerator) {
            PairingGeneratorView()
                .environmentObject(model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GlassCircleButton(systemImage: "chevron.left", size: 40, action: onBack)
                Spacer()
                GlassCircleButton(systemImage: "gearshape", size: 40, action: onSettings)
            }

            Text(t("lab.title"))
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(SceneKind.descent.textPrimary)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 3)

            Text(t("lab.subtitle"))
                .font(.system(size: 13))
                .tracking(0.6)
                .foregroundStyle(SceneKind.descent.textSecondary)
        }
        .padding(.bottom, 4)
    }

    private var sectionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            sectionCard(.apps, icon: "bolt.badge.clock", titleKey: "lab.apps", detailKey: "lab.appsDetail")
            sectionCard(.pairing, icon: "doc.badge.key", titleKey: "lab.pairing", detailKey: "lab.pairingDetail")
            sectionCard(.scripts, icon: "curlybraces", titleKey: "lab.scripts", detailKey: "lab.scriptsDetail")
            sectionCard(.logs, icon: "text.alignleft", titleKey: "lab.logs", detailKey: "lab.logsDetail")
        }
    }

    private func sectionCard(_ route: LabRoute, icon: String, titleKey: String, detailKey: String) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(height: 26)
                Text(t(titleKey))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(t(detailKey))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(height: 138, alignment: .top)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var generatorCard: some View {
        Button {
            showGenerator = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("lab.generator"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(t("lab.generatorDetail"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var repoRow: some View {
        Button(action: onRepo) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .regular))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("lab.repo"))
                        .font(.system(size: 14, weight: .medium))
                    Text(t("lab.repoDetail"))
                        .font(.system(size: 11))
                        .opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 配对分区

struct PairingSectionView: View {
    @EnvironmentObject var model: AppModel
    var onGenerate: () -> Void

    @State private var showImporter = false

    private func t(_ key: String) -> String {
        L10n.t(key, model.language)
    }

    var body: some View {
        ZStack {
            SkyBackground(kind: .mountain)
            Color.black.opacity(SceneKind.mountain.veil).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    if !model.pairingMeta.isEmpty {
                        metaCard
                    }
                    actions
                }
                .padding(18)
            }
        }
        .navigationTitle(t("pairing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                showImporter = false
                guard let url = urls.first else { return }
                model.importPairing(from: url)
            }
            .ignoresSafeArea()
        }
        .onAppear { model.refreshPairingState() }
    }

    private var statusCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: model.pairingExists ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(model.pairingExists ? Color(red: 0.55, green: 0.95, blue: 0.75) : Color(red: 1.0, green: 0.72, blue: 0.45))
                    Text(model.pairingExists ? t("pairing.ready") : t("pairing.missing"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text(t("pairing.kind"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(model.pairingKind.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var metaCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                if let udid = model.pairingMeta["UDID"] {
                    metaRow(t("pairing.udid"), udid)
                }
                metaRow(t("pairing.host"),
                        model.pairingMeta["HasHostCert"] == "1" && model.pairingMeta["HasRootCert"] == "1" ? "OK" : "—")
                if let wifi = model.pairingMeta["WiFiMAC"] {
                    metaRow("Wi-Fi MAC", wifi)
                }
            }
        }
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                showImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                    Text(t("pairing.import"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Button(action: onGenerate) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text(t("lab.generator"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
