//
//  UpdateSigningView.swift
//  JIT RPOQ
//
//  更新前配置签名材料：p12 + 描述文件（或 Apple ID 证书只给 p12），
//  确认后交给云端 Mac 重签，完成后走苹果无线安装协议覆盖安装。
//

import SwiftUI

struct UpdateSigningView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SigningMode = .certificate
    @State private var p12URL: URL?
    @State private var profileURL: URL?
    @State private var password = ""
    @State private var pat = Keychain.get("GITHUB_PAT") ?? ""
    @State private var pickTarget: PickTarget?
    @State private var showPicker = false

    private enum PickTarget: String, Identifiable {
        case p12, profile
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    modeCard
                    materialCard
                    secretCard
                    actionCard
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("更新签名配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in
                    showPicker = false
                    guard let url = urls.first, let target = pickTarget else { return }
                    switch target {
                    case .p12: p12URL = url
                    case .profile: profileURL = url
                    }
                    pickTarget = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "signature")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("更新前先签名")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("新版本 v\(model.signingVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            Text("苹果的无线安装协议只认已签名的 IPA。把 p12（和描述文件）交出去，云端 Mac 会用它们重签最新未签名包，签完生成安装清单，再点一下就直接覆盖安装。材料只用于这一次签名。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private var modeCard: some View {
        Card(title: "选择证书类型", systemImage: "person.badge.key") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("证书类型", selection: $mode) {
                    Text("证书签名").tag(SigningMode.certificate)
                    Text("Apple ID 证书").tag(SigningMode.appleID)
                }
                .pickerStyle(.segmented)
                .disabled(model.signingBusy)

                Text(mode == .certificate
                     ? "需要 p12 证书 + mobileprovision 描述文件。描述文件里带 get-task-allow 时，签出来的包才能开 JIT。"
                     : "Apple ID 签名证书只有 p12，没有单独的描述文件；云端会按 p12 里的团队信息补描述文件，补不到会提示你手动导入。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var materialCard: some View {
        Card(title: "签名材料", systemImage: "doc.badge.plus") {
            VStack(spacing: 10) {
                materialRow(
                    title: "p12 证书",
                    detail: p12URL?.lastPathComponent,
                    icon: "key.fill"
                ) {
                    pickTarget = .p12
                    showPicker = true
                }

                if mode == .certificate {
                    materialRow(
                        title: "mobileprovision 描述文件",
                        detail: profileURL?.lastPathComponent,
                        icon: "doc.text.fill"
                    ) {
                        pickTarget = .profile
                        showPicker = true
                    }
                }
            }
        }
    }

    private func materialRow(title: String, detail: String?, icon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail ?? "未选择")
                    .font(.system(size: 11))
                    .foregroundStyle(detail == nil ? Theme.textSecondary : Theme.green)
                    .lineLimit(1)
            }
            Spacer()
            Button("导入") { action() }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .disabled(model.signingBusy)
        }
        .padding(10)
        .background(Theme.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var secretCard: some View {
        Card(title: "密码与权限", systemImage: "lock.fill") {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("p12 密码")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 84, alignment: .leading)
                    SecureField("导出 p12 时设置的密码", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(Theme.cardAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack(spacing: 8) {
                    Text("GitHub PAT")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 84, alignment: .leading)
                    SecureField("repo + workflow 权限", text: $pat)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(Theme.cardAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Text("PAT 只用来把材料写进仓库 Secrets 并触发签名流水线，不会写进代码。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionCard: some View {
        Card(title: "签名并安装", systemImage: "arrow.down.app") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if model.signingBusy {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Image(systemName: model.signingDone ? "checkmark.seal.fill" : "circle.dotted")
                            .foregroundStyle(model.signingDone ? Theme.green : Theme.textSecondary)
                    }
                    Text(model.signingStatus)
                        .font(.system(size: 12, weight: model.signingDone ? .semibold : .regular))
                        .foregroundStyle(model.signingDone ? Theme.green : Theme.textSecondary)
                }

                if model.signingDone {
                    ActionButton(title: "打开无线安装", systemImage: "arrow.down.circle.fill", prominent: true) {
                        model.openOTAInstall()
                        dismiss()
                    }
                    Text("系统会提示「在“JIT RPOQ”中打开」，确认后开始下载并覆盖安装，配对文件和设置都会保留。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ActionButton(
                        title: model.signingBusy ? "签名中…" : "确认并开始云端签名",
                        systemImage: "checkmark.seal",
                        prominent: true,
                        disabled: model.signingBusy || p12URL == nil
                    ) {
                        model.submitUpdateSigning(
                            mode: mode,
                            p12URL: p12URL,
                            profileURL: mode == .certificate ? profileURL : nil,
                            password: password,
                            pat: pat
                        )
                    }
                }
            }
        }
    }
}
