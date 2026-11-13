//
//  UpdatePromptView.swift
//  JIT RPOQ
//

import SwiftUI

struct UpdatePromptView: View {
    let update: AppUpdate
    let onInstall: () -> Void
    let onAdvancedSign: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("发现新版本")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text("v\(update.version)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text("当前 v\(UpdateChecker.currentVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            if let notes = update.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("点「下载新版本」会打开下载页，拿到 IPA 后用你自己的签名工具（全能签 / 小白签 / 个人证书）签名安装，覆盖旧版本即可，配对文件和设置都会保留。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ActionButton(title: "下载新版本", systemImage: "arrow.down.app.fill", prominent: true) {
                    onInstall()
                }
                Button {
                    onAdvancedSign()
                } label: {
                    Text("高级：云端签名后无线安装")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                ActionButton(title: "稍后再说", systemImage: "clock") {
                    onLater()
                }
            }
        }
        .padding(20)
        .background(Theme.background)
        .presentationDetents([.height(370)])
        .presentationDragIndicator(.visible)
    }
}
