//
//  PairingGeneratorView.swift
//  JIT RPOQ
//

import SwiftUI
import UIKit

@MainActor
final class PairingGeneratorModel: ObservableObject {
    @Published var running = false
    @Published var pin: String?
    @Published var status: String = "还没有开始"
    @Published var lines: [String] = []
    @Published var finished = false

    private var generator: PairingGenerator?

    var onSuccess: ((URL) -> Void)?

    func start() {
        guard !running else { return }
        let gen = PairingGenerator()
        generator = gen
        pin = nil
        lines = []
        finished = false
        running = true
        status = "正在广播配对服务…"

        gen.onPin = { [weak self] code in
            Task { @MainActor in
                self?.pin = code
                self?.append("收到配对码：\(code)")
            }
        }
        gen.onStatus = { [weak self] text in
            Task { @MainActor in
                self?.status = text
                self?.append(text)
            }
        }
        gen.onFinish = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.handleFinish(result)
            }
        }
        gen.start()
    }

    private func handleFinish(_ result: Result<URL, Error>) {
        running = false
        switch result {
            case .success(let url):
                finished = true
                pin = nil
                status = "配对成功，配对文件已自动导入"
                append("配对文件已写入：\(url.lastPathComponent)")
                onSuccess?(url)
            case .failure(let error):
                pin = nil
                status = "配对未完成：\(error.localizedDescription)"
                append(error.localizedDescription)
            }
    }

    func cancel() {
        generator?.cancelPairing()
        generator = nil
        running = false
        pin = nil
        status = "已取消"
        append("用户取消配对")
    }

    private func append(_ line: String) {
        lines.append(line)
    }
}

struct PairingGeneratorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PairingGeneratorModel()

    private var systemVersion: String {
        UIDevice.current.systemVersion
    }

    private var isIOS27: Bool {
        (Int(systemVersion.split(separator: ".").first ?? "0") ?? 0) >= 27
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    stepsCard
                    controlCard
                    if !vm.lines.isEmpty {
                        logCard
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("一键生成配对文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        if vm.running { vm.cancel() }
                        dismiss()
                    }
                }
            }
            .onAppear {
                vm.onSuccess = { _ in
                    model.applyGeneratedPairing()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iOS 27 本机配对")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("设备自己发起配对，全程不需要电脑")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("iOS 27 新增了由设备主动发起的配对：App 在局域网里充当一台「电脑」并广播配对服务，你在「设置 › 隐私与安全性 › 开发者模式」里点一下，输入配对码，配对文件就直接生成在这台设备上。iOS 26 及以下没有这个能力，仍需电脑生成后导入。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StatusPill(text: "当前系统 iOS \(systemVersion)", ok: isIOS27)
                StatusPill(text: isIOS27 ? "支持本机配对" : "仅 iOS 27 支持", ok: isIOS27)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private var stepsCard: some View {
        Card(title: "怎么操作", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 12) {
                step(1, "点下面的「开始配对」", "第一次会弹「允许本地网络」，必须点允许。")
                step(2, "打开 设置 › 隐私与安全性 › 开发者模式", "滑到页面最下面，能看到一个待配对的设备名字。")
                step(3, "点「Pair with JIT RPOQ」", "名字就是本 App；点它之后 iPhone 会连到 App。")
                step(4, "输入 App 上显示的 6 位配对码", "配对码会以大号数字显示在下面，可能同时出现在通知里。")
                step(5, "配对完成后回到 App", "成功会自动写入配对文件并导入，直接回主页，不用再手动选文件。")
            }

            Divider().background(Theme.stroke)

            VStack(alignment: .leading, spacing: 6) {
                Text("App 会帮你做什么")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                bullet("广播 _remotepairing-pairable-host._tcp 服务，让设置页发现本 App")
                bullet("保持后台运行，等你从设置里连过来")
                bullet("显示 6 位配对码，完成握手")
                bullet("把配对文件写进 App 沙盒，自动导入并刷新配对状态")
            }
        }
    }

    private func step(_ index: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(Theme.green).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controlCard: some View {
        Card(title: "配对", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(spacing: 12) {
                Text(vm.status)
                    .font(.system(size: 12))
                    .foregroundStyle(vm.finished ? Theme.green : Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let pin = vm.pin {
                    VStack(spacing: 6) {
                        Text("配对码")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Text(pin)
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .tracking(6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if vm.running {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text("正在等待设备连接，请留在设置页完成配对")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    ActionButton(
                        title: vm.running ? "配对中…" : (vm.finished ? "重新配对" : "开始配对"),
                        systemImage: "play.fill",
                        prominent: true,
                        disabled: vm.running || !isIOS27
                    ) {
                        vm.start()
                    }
                    if vm.running {
                        ActionButton(title: "取消", systemImage: "xmark") {
                            vm.cancel()
                        }
                    }
                }

                if !isIOS27 {
                    Text("当前系统是 iOS \(systemVersion)，一键生成配对文件只在 iOS 27 及以上可用；iOS 26 请用电脑生成经典 / RPP 配对文件后导入。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var logCard: some View {
        Card(title: "配对日志", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(vm.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
