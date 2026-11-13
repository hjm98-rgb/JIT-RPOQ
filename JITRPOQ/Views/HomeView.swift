//
//  HomeView.swift
//  JIT RPOQ
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showImporter = false
    @State private var showGenerator = false
    @State private var showTextImport = false
    @State private var pastedText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    vpnBanner
                    hero
                    pairingCard
                    vpnCard
                    quickActions
                    automationCard
                    tipsCard
                    updateCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("JIT RPOQ")
            .onAppear {
                model.probeVPN()
                model.loadIconsIfNeeded()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.runDiagnostics()
                    } label: {
                        Image(systemName: "stethoscope")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                showImporter = false
                guard let url = urls.first else { return }
                model.importPairing(from: url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showGenerator) {
            PairingGeneratorView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showTextImport) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("把配对文件里的 plist 全文粘贴进来（支持 base64）")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    TextEditor(text: $pastedText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Theme.cardAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(minHeight: 260)
                    HStack(spacing: 10) {
                        ActionButton(title: "存为经典配对", systemImage: "doc.badge.plus", prominent: true) {
                            model.importPairingFromText(pastedText, kind: .classic)
                            showTextImport = false
                        }
                        ActionButton(title: "存为 RPP 配对", systemImage: "network") {
                            model.importPairingFromText(pastedText, kind: .rpp)
                            showTextImport = false
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("粘贴配对文件")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { showTextImport = false }
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var vpnBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: model.vpnConnected ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(model.vpnConnected ? Theme.green : Theme.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.vpnConnected ? "VPN 已开启" : "VPN 未开启")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.vpnConnected
                     ? "LocalDevVPN 回环已连接，可以开 JIT"
                     : "请打开 LocalDevVPN 并连接，否则无法连接设备")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                model.probeVPN()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background((model.vpnConnected ? Theme.green : Theme.red).opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((model.vpnConnected ? Theme.green : Theme.red).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.9), Theme.accent2.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.82))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("一键 JIT")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("RPP 隧道 · 自动附加 · iOS 26 脚本")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                StatusPill(text: model.pairingExists ? "配对已就绪" : "缺少配对文件", ok: model.pairingExists)
                StatusPill(text: model.vpnConnected ? "回环已连接" : "VPN 未连接", ok: model.vpnConnected)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Theme.card, Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var pairingCard: some View {
        Card(title: "配对文件", systemImage: "doc.badge.key") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.pairingExists ? model.pairingKind.rawValue : "尚未导入")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.pairingExists ? "pairing.mobiledevicepairing" : "必须先导入配对文件才能开启 JIT")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if model.pairingExists {
                    StatusPill(text: "有效", ok: true)
                }
            }

            if model.pairingExists {
                VStack(spacing: 6) {
                    if let udid = model.pairingMeta["UDID"] {
                        InfoRow(label: "UDID", value: udid)
                    }
                    InfoRow(label: "主机证书", value: model.pairingMeta["HasHostCert"] == "1" ? "已包含" : "缺失")
                    InfoRow(label: "设备证书", value: model.pairingMeta["HasDeviceCert"] == "1" ? "已包含" : "缺失")
                }
                .padding(10)
                .background(Theme.cardAlt)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            ActionButton(title: "一键生成配对文件（iOS 27）", systemImage: "wand.and.stars") {
                showGenerator = true
            }

            HStack(spacing: 10) {
                ActionButton(title: "导入配对文件", systemImage: "square.and.arrow.down", prominent: true) {
                    showImporter = true
                }
                ActionButton(title: "粘贴文本", systemImage: "doc.on.clipboard") {
                    showTextImport = true
                }
            }
            if model.pairingExists {
                ActionButton(title: "移除配对文件", systemImage: "trash") {
                    model.deletePairing()
                }
            }
        }
    }

    private var vpnCard: some View {
        Card(title: "LocalDevVPN 回环", systemImage: "network") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.vpnConnected ? "10.7.0.1 可连接" : "需要先连接 VPN")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.vpnConnected ? "端口 \(model.vpnPort.map(String.init) ?? "—")" : model.vpnMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                StatusPill(text: model.vpnConnected ? "在线" : "离线", ok: model.vpnConnected)
            }
            HStack(spacing: 10) {
                ActionButton(title: "重新检测", systemImage: "arrow.clockwise") {
                    model.probeVPN()
                }
                ActionButton(title: "打开 LocalDevVPN", systemImage: "arrow.up.right.square") {
                    if let url = URL(string: "localdevvpn://") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        Card(title: "快捷操作", systemImage: "bolt.circle") {
            if let active = model.sessionBundle {
                HStack(spacing: 10) {
                    StatusPill(text: "JIT 会话运行中", ok: true)
                    Text(active)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button("停止") {
                        model.stopSession()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.red)
                }
            }
            if let bundle = model.lastBundleID, let app = model.app(named: bundle) {
                HStack(spacing: 10) {
                    PackageIcon(image: model.icon(for: app.bundleID), name: app.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(app.bundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                ActionButton(title: "再次开启 JIT", systemImage: "bolt.fill", prominent: true, disabled: model.busyBundle != nil) {
                    model.enable(app)
                }
            } else {
                Text("还没有开过 JIT 的应用，去「应用」页选一个。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                ActionButton(title: "刷新应用", systemImage: "arrow.triangle.2.circlepath", disabled: model.isLoadingApps) {
                    model.refreshApps()
                }
                ActionButton(title: "一键自检", systemImage: "checkmark.shield") {
                    model.runDiagnostics()
                }
            }
            ActionButton(title: "一键补齐配置", systemImage: "wrench.and.screwdriver.fill", prominent: true, disabled: !model.pairingExists) {
                model.oneTapSetup()
            }
            ActionButton(title: "导出配对文件（给其他启动器用）", systemImage: "square.and.arrow.up", disabled: !model.pairingExists) {
                model.exportPairingForOtherLaunchers()
            }
        }
    }

    private var automationCard: some View {
        Card(title: "自动开启", systemImage: "wand.and.stars") {
            Toggle(isOn: $model.autoMode) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("点击应用即自动开 JIT")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("不用再回启动器点第二次")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)

            Toggle(isOn: $model.useIOS26Script) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("iOS 26 脚本模式")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("用内置 JIT 页脚本处理 brk #0xf00d")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)

            Text("外部应用跳转：jitrpoq://enable?bundle=你的BundleID")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
    }

    private var updateCard: some View {
        Card(title: "版本与更新", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前版本 v\(model.currentVersion)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.checkingUpdate ? "正在检查…" : (model.availableUpdate == nil ? "点右侧检查是否有新版本" : "发现新版本 v\(model.availableUpdate?.version ?? "")"))
                        .font(.system(size: 11))
                        .foregroundStyle(model.availableUpdate == nil ? Theme.textSecondary : Theme.green)
                }
                Spacer()
                if model.availableUpdate != nil {
                    Button("立即更新") { model.installUpdate() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Button("检查更新") { model.checkForUpdates(force: true) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .disabled(model.checkingUpdate)
                }
            }
        }
    }

    private var tipsCard: some View {
        Card(title: "使用顺序", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 8) {
                tip("1", "导入配对文件（经典或 RPP）")
                tip("2", "打开 LocalDevVPN 并连接")
                tip("3", "在「应用」页点一下目标应用，自动开 JIT")
                tip("4", "应用退出后重开时再点一次，或让它跳 jitrpoq://enable")
            }
        }
    }

    private func tip(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Theme.accent.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }
}
