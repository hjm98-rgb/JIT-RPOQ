//
//  SigningView.swift
//  JIT RPOQ
//
//  证书 / 描述文件管理：导入 Apple ID 签名的 mobileprovision 与 p12，
//  检查 get-task-allow，导出到「文件」App，方便复用同一套签名材料。
//

import SwiftUI
import UIKit

struct SigningView: View {
    @EnvironmentObject var model: AppModel

    @State private var showProfilePicker = false
    @State private var showP12Picker = false
    @State private var pendingP12: URL?
    @State private var appleID = ""
    @State private var applePassword = ""
    @State private var certPassword = ""
    @State private var pat = ""
    @State private var teamID = ""
    @State private var bundleID = "com.rpoq.jitlauncher"
    @State private var showPasswordPrompt = false
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    introCard
                    profileCard
                    identityCard
                    matchCard
                    exportCard
                    cloudCard
                    helpCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("签名")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProfilePicker) {
                DocumentPicker { urls in
                    showProfilePicker = false
                    if let url = urls.first { model.importProfile(from: url) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showP12Picker) {
                DocumentPicker { urls in
                    showP12Picker = false
                    guard let url = urls.first else { return }
                    pendingP12 = url
                    password = ""
                    showPasswordPrompt = true
                }
                .ignoresSafeArea()
            }
            .alert("输入 p12 密码", isPresented: $showPasswordPrompt) {
                SecureField("密码", text: $password)
                Button("导入") {
                    if let url = pendingP12 {
                        model.importP12(from: url, password: password)
                    }
                    pendingP12 = nil
                }
                Button("取消", role: .cancel) { pendingP12 = nil }
            } message: {
                Text("这是导出证书时设置的密码，不是 Apple ID 密码。")
            }
        }
    }

    private var introCard: some View {
        Card(title: "Apple ID 签名材料", systemImage: "checkmark.seal") {
            Text("Apple ID（个人团队）签出来的 App 天生带 get-task-allow，所以能开 JIT。把同一份描述文件和证书放进来，就能确认它到底有没有 JIT 权限，也能导出复用。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var profileCard: some View {
        Card(title: "描述文件", systemImage: "doc.badge.gearshape") {
            if let profile = model.profile {
                infoRow("名称", profile.name)
                infoRow("App ID", profile.applicationIdentifier)
                infoRow("Team", "\(profile.teamName)（\(profile.teamID)）")
                infoRow("有效期", dateText(profile.expiration))
                infoRow("设备数", "\(profile.devices.count)")
                HStack {
                    StatusPill(text: profile.isJITCapable ? "含 get-task-allow" : "无 JIT 权限",
                               ok: profile.isJITCapable)
                    Spacer()
                }
            } else {
                Text("还没有导入 .mobileprovision")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ActionButton(title: model.profile == nil ? "导入描述文件" : "更换描述文件",
                         systemImage: "square.and.arrow.down",
                         prominent: model.profile == nil) {
                showProfilePicker = true
            }
        }
    }

    private var identityCard: some View {
        Card(title: "签名证书", systemImage: "person.badge.key") {
            if let subject = model.identitySubject {
                infoRow("证书", subject)
                HStack {
                    StatusPill(text: "已导入 p12", ok: true)
                    Spacer()
                }
            } else {
                Text("还没有导入 .p12 证书")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ActionButton(title: model.identitySubject == nil ? "导入 p12 证书" : "更换证书",
                         systemImage: "key.horizontal",
                         prominent: false) {
                showP12Picker = true
            }
        }
    }

    private var matchCard: some View {
        Card(title: "匹配检查", systemImage: "checkmark.circle") {
            if model.profile != nil && model.identitySubject != nil {
                HStack(spacing: 10) {
                    StatusPill(text: model.identityMatchesProfile ? "证书与描述文件匹配" : "不匹配",
                               ok: model.identityMatchesProfile)
                    Spacer()
                }
                Text(model.identityMatchesProfile
                     ? "这套材料可以签出带 JIT 权限的 App，任何 JIT 启动器都能附加。"
                     : "描述文件里没有这张证书，签出来的 App 装不上或没有 JIT 权限。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("导入描述文件和证书后自动比对")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var exportCard: some View {
        Card(title: "导出", systemImage: "square.and.arrow.up") {
            Text("导出到 文件 App › JIT RPOQ › Export，可以再导入其他签名工具，或备份到 iCloud。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(title: "导出描述文件与证书",
                         systemImage: "tray.and.arrow.up.fill",
                         prominent: true,
                         disabled: model.profileRawData == nil && model.identityP12Data == nil) {
                model.exportSigningAssets()
            }
        }
    }

    private var cloudCard: some View {
        Card(title: "Apple ID 云签名", systemImage: "cloud") {
            Text("用云端真实 Mac 登录 Apple 开发者门户（设备信息由 macOS 自身提供，不用伪造），自动申请开发证书和描述文件，重签 IPA，并把证书打包成 p12 导出。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            field("Apple ID", text: $appleID, secure: false)
            field("App 专用密码", text: $applePassword, secure: true)
            field("证书导出密码（自定义）", text: $certPassword, secure: true)
            field("GitHub PAT（repo + admin）", text: $pat, secure: true)
            field("Team ID（可留空）", text: $teamID, secure: false)
            field("Bundle ID", text: $bundleID, secure: false)

            HStack(spacing: 8) {
                StatusPill(text: model.cloudStatus, ok: model.cloudStatus.contains("完成"))
                Spacer()
                if model.cloudRunning {
                    ProgressView().tint(Theme.accent)
                }
            }

            ActionButton(title: "登录并开始签名",
                         systemImage: "person.badge.key.fill",
                         prominent: true,
                         disabled: model.cloudRunning) {
                model.startCloudSign(appleID: appleID,
                                     password: applePassword,
                                     certPassword: certPassword,
                                     pat: pat,
                                     teamID: teamID,
                                     bundleID: bundleID)
            }

            if let link = model.cloudRunURL, let url = URL(string: link) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("打开发布页下载 IPA / 证书")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            appleID = Keychain.get("APPLE_ID") ?? ""
            pat = Keychain.get("GITHUB_PAT") ?? ""
            certPassword = Keychain.get("CERT_PASSWORD") ?? ""
        }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.cardAlt)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var helpCard: some View {
        Card(title: "为什么 Apple ID 签名能开 JIT", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                bullet("个人团队描述文件的 Entitlements 里带 get-task-allow，这是调试权限，它允许调试器附加进程，JIT 就是靠这个打开的。")
                bullet("登录 Apple ID + 双重认证，是让 Apple 给你签发这张开发证书和描述文件；设备 UDID 会被写进 ProvisionedDevices。")
                bullet("所以同一个 App，用企业证书签没有 JIT，用 Apple ID 个人证书签就有 JIT。")
                bullet("证书和描述文件都能从签名工具导出成文件，之后可以重复使用，直到描述文件到期。")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
