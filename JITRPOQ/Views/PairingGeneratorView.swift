//
//  PairingGeneratorView.swift
//  JIT RPOQ
//
//  iOS 27 一键生成配对文件：本机扮演局域网电脑，设备在开发者模式里主动配对。
//

import SwiftUI
import UIKit

struct PairingGeneratorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var host: WirelessPairingHost?
    @State private var running = false
    @State private var pin: String?
    @State private var statusLines: [String] = []
    @State private var errorText: String?
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var supportsWirelessPairing: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    noticeCard
                    if supportsWirelessPairing {
                        stepsCard
                        if running || pin != nil {
                            pinCard
                        }
                        actionCard
                        if !statusLines.isEmpty {
                            logCard
                        }
                    } else {
                        unsupportedCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("一键生成配对文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { stopAndDismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .onDisappear { stopAll() }
        }
    }

    // MARK: - 卡片

    private var noticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: supportsWirelessPairing ? "wifi.badge.checkmark" : "exclamationmark.triangle.fill")
                    .foregroundStyle(supportsWirelessPairing ? Theme.green : Theme.orange)
                Text(supportsWirelessPairing ? "iOS 27 设备端无线配对" : "仅支持 iOS 27 及以上")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("iOS 27 新增了「无线配对」：设备可以在局域网里主动找一台“电脑”配对，不再需要数据线、也不需要另一台 Mac/PC。JIT RPOQ 会扮演这台电脑，配对完成后配对文件自动保存并自动导入。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((supportsWirelessPairing ? Theme.green : Theme.orange).opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((supportsWirelessPairing ? Theme.green : Theme.orange).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stepsCard: some View {
        Card(title: "配对流程", systemImage: "list.number") {
            stepSection(
                title: "应用会自动做这些",
                items: [
                    "生成一对新的主机密钥，作为“电脑”的身份",
                    "在局域网广播配对服务（_remotepairing-pairable-host）",
                    "等设备连上来，显示 6 位配对码",
                    "配对完成后把配对文件写进沙盒，自动导入"
                ],
                color: Theme.accent
            )
            Divider().overlay(Theme.stroke)
            stepSection(
                title: "你需要做这些",
                items: [
                    "让 iPad 连着 Wi-Fi（不需要连电脑，也不需要 LocalDevVPN 来配对）",
                    "点下面的「开始配对」，允许「本地网络」权限",
                    "打开 设置 › 隐私与安全性 › 开发者模式，滑到最下面",
                    "点「与 JIT RPOQ 配对」，输入这里显示的 6 位码",
                    "配对期间别锁屏、别切太远，30 秒内完成"
                ],
                color: Theme.green
            )
        }
    }

    private func stepSection(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 18, height: 18)
                        .background(color.opacity(0.25))
                        .clipShape(Circle())
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pinCard: some View {
        Card(title: "配对码", systemImage: "number.square") {
            VStack(spacing: 10) {
                if let pin {
                    Text(pin)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.vertical, 6)
                    Text("在 设置 › 隐私与安全性 › 开发者模式 › 与 JIT RPOQ 配对 里输入这 6 位")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.accent)
                        Text("等待设备发起配对…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 12)
                }
                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            if running {
                ActionButton(title: "取消配对", systemImage: "xmark.circle", prominent: false) {
                    stopAll()
                    running = false
                    pin = nil
                    errorText = nil
                    statusLines.append("已取消")
                }
            } else {
                ActionButton(title: "开始配对", systemImage: "wifi", prominent: true) {
                    start()
                }
            }
            Text("配对成功后会自动回到主页，配对文件自动导入，不需要再手动选择文件。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var logCard: some View {
        Card(title: "配对日志", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(statusLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var unsupportedCard: some View {
        Card(title: "当前系统不支持", systemImage: "nosign") {
            Text("当前系统是 iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)。设备端无线配对是 iOS 27 才加入的能力，iOS 26 及以下只能用电脑或另一台设备生成配对文件，再回到「配对文件」卡片导入。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func start() {
        guard supportsWirelessPairing, !running else { return }
        running = true
        pin = nil
        errorText = nil
        statusLines = []
        statusLines.append("正在生成主机身份…")

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "pairing.session") {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
        UIApplication.shared.isIdleTimerDisabled = true

        let host = WirelessPairingHost(
            log: { line in
                Task { @MainActor in append(line) }
            },
            onPin: { code in
                Task { @MainActor in
                    pin = code
                    append("配对码已生成：\(code)")
                }
            },
            completion: { result in
                Task { @MainActor in handle(result) }
            }
        )
        self.host = host

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try host.start()
            } catch {
                Task { @MainActor in
                    errorText = error.localizedDescription
                    running = false
                    append("启动失败：\(error.localizedDescription)")
                    stopAll()
                }
            }
        }
    }

    private func handle(_ result: Swift.Result<WirelessPairingHost.Result, Error>) {
        switch result {
        case .success(let pairing):
            append("配对完成：\(pairing.deviceName ?? "未知设备")")
            running = false
            UIApplication.shared.isIdleTimerDisabled = false
            endBackgroundTask()
            model.importGeneratedPairing(at: pairing.url, deviceName: pairing.deviceName)
            dismiss()
            model.requestHome()
        case .failure(let error):
            errorText = error.localizedDescription
            running = false
            append("配对失败：\(error.localizedDescription)")
            stopAll()
        }
    }

    private func append(_ line: String) {
        model.append("[配对] \(line)")
        statusLines.append(line)
    }

    private func stopAll() {
        host?.stop()
        host = nil
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func stopAndDismiss() {
        stopAll()
        running = false
        dismiss()
    }
}
