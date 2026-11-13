//
//  AppModel.swift
//  JIT RPOQ
//

import Foundation
import Combine
import SwiftUI
import UIKit

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
    let isError: Bool
}

enum PairingKind: String {
    case classic = "经典配对文件"
    case rpp = "RPP 配对文件（iOS 26）"
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var pairingExists = false
    @Published var pairingKind: PairingKind = .classic
    @Published var pairingMeta: [String: String] = [:]
    @Published var vpnConnected = false
    @Published var vpnPort: UInt16?
    @Published var vpnMessage = "未检测"
    @Published var apps: [InstalledApp] = []
    @Published var icons: [String: Data] = [:]
    @Published var isLoadingApps = false
    @Published var logs: [LogEntry] = []
    @Published var busyBundle: String?
    @Published var lastError: String?
    @Published var toast: String?

    @Published var autoMode: Bool {
        didSet { UserDefaults.standard.set(autoMode, forKey: "autoMode") }
    }
    @Published var useIOS26Script: Bool {
        didSet { UserDefaults.standard.set(useIOS26Script, forKey: "useIOS26Script") }
    }
    @Published var lastBundleID: String? {
        didSet { UserDefaults.standard.set(lastBundleID, forKey: "lastBundleID") }
    }
    @Published var favourites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favourites), forKey: "favourites") }
    }

    @Published var sessionBundle: String?
    @Published var homeRequest = UUID()
    @Published var profile: ProvisioningProfile?
    @Published var profileFileName: String?
    @Published var profileRawData: Data?
    @Published var identitySubject: String?
    @Published var identityCertDER: Data?
    @Published var identityP12Data: Data?
    @Published var identityMatchesProfile = false
    @Published var cloudRunning = false
    @Published var cloudStatus = "未开始"
    @Published var cloudRunURL: String?
    @Published var batchRunning = false
    @Published var batchTotal = 0
    @Published var batchDone = 0
    private var vpnTimer: Timer?
    private var vpnProbing = false
    private var iconLoading = false
    private var didAutoRefresh = false
    var activeSession: JITSession?
    private var pendingAutoBundle: String?

    private init() {
        autoMode = UserDefaults.standard.object(forKey: "autoMode") as? Bool ?? true
        useIOS26Script = UserDefaults.standard.object(forKey: "useIOS26Script") as? Bool ?? true
        lastBundleID = UserDefaults.standard.string(forKey: "lastBundleID")
        favourites = Set(UserDefaults.standard.stringArray(forKey: "favourites") ?? [])
        JITEngine.shared.setLogSink { [weak self] line in
            Task { @MainActor in self?.append(line, error: false) }
        }
        loadCachedIcons()
        refreshPairingState()
        probeVPN()
        startVPNMonitor()
    }

    private func startVPNMonitor() {
        vpnTimer?.invalidate()
        vpnTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeVPN() }
        }
        if let vpnTimer {
            RunLoop.main.add(vpnTimer, forMode: .common)
        }
    }

    // MARK: - 日志

    func append(_ text: String, error: Bool = false) {
        logs.append(LogEntry(time: Date(), text: text, isError: error))
        if logs.count > 800 { logs.removeFirst(logs.count - 800) }
    }

    func clearLogs() { logs.removeAll() }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        append(error.localizedDescription, error: true)
    }

    // MARK: - 配对

    func refreshPairingState() {
        pairingExists = JITEngine.shared.hasPairingFile()
        guard pairingExists else {
            pairingMeta = [:]
            return
        }
        let url = JITEngine.shared.pairingFileURL()
        pairingMeta = JITEngine.shared.pairingMetadata(at: url)
        let hasCerts = (pairingMeta["HasHostCert"] == "1" && pairingMeta["HasDeviceCert"] == "1")
        pairingKind = (pairingMeta["UDID"] != nil || hasCerts) ? .classic : .rpp
        if let kind = UserDefaults.standard.string(forKey: "pairingKind"), let parsed = PairingKind(rawValue: kind) {
            pairingKind = parsed
        }
    }

    /// 导入配对文件。文件已由 DocumentPicker(asCopy) 复制进沙盒，直接读就行。
    /// kind 传 nil 时自动识别：能读出证书链的算经典，读不出结构的算 RPP。
    func importPairing(from url: URL, kind: PairingKind? = nil) {
        append("开始导入：\(url.lastPathComponent)")
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            let data = try Data(contentsOf: url)
            if accessing { url.stopAccessingSecurityScopedResource() }

            guard data.count > 100 else {
                throw JITEngineError.pairingInvalid("文件内容太小，可能选错了")
            }

            let destination = JITEngine.shared.pairingFileURL()
            try data.write(to: destination, options: .atomic)
            _ = try JITEngine.shared.validatePairingFile(at: destination)

            let detected = kind ?? Self.detectKind(at: destination)
            UserDefaults.standard.set(detected.rawValue, forKey: "pairingKind")
            refreshPairingState()
            pairingKind = detected
            toast = "配对文件已导入：\(detected.rawValue)"
            append("已导入配对文件 \(url.lastPathComponent)（\(detected.rawValue)）")
        } catch {
            fail(error)
        }
    }

    static func detectKind(at url: URL) -> PairingKind {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = object as? [String: Any] else {
            return .rpp
        }
        // 带完整证书链 + UDID 的，是 idevicepair / 爱思 那类经典配对记录；
        // iLoader 这类工具导出的 .mobiledevicepair 通常只有证书链没有 UDID，
        // 供 iOS 26 的 RPP 隧道使用，归为 RPP。
        guard dict["HostCertificate"] != nil, dict["DeviceCertificate"] != nil else {
            return .rpp
        }
        return dict["UDID"] != nil ? .classic : .rpp
    }

    /// 把剪贴板里的配对 plist 文本存成文件。
    /// iOS 27 本机配对完成后：配对文件已在沙盒里，直接校验 + 生效。
    func applyGeneratedPairing() {
        do {
            _ = try JITEngine.shared.validatePairingFile()
            UserDefaults.standard.set(PairingKind.rpp.rawValue, forKey: "pairingKind")
            pairingKind = .rpp
            refreshPairingState()
            toast = "本机配对完成，配对文件已自动导入"
            append("iOS 27 本机配对成功，配对文件已自动导入")
        } catch {
            fail(error)
        }
    }

    func importPairingFromText(_ text: String, kind: PairingKind = .classic) {
        do {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<plist") || trimmed.hasPrefix("bplist") else {
                throw JITEngineError.pairingInvalid("内容不像 plist")
            }
            var data: Data
            if let raw = Data(base64Encoded: trimmed) {
                data = raw
            } else {
                data = Data(trimmed.utf8)
            }
            let destination = JITEngine.shared.pairingFileURL()
            try data.write(to: destination, options: .atomic)
            _ = try JITEngine.shared.validatePairingFile(at: destination)
            UserDefaults.standard.set(kind.rawValue, forKey: "pairingKind")
            refreshPairingState()
            pairingKind = kind
            toast = "配对文件已写入"
        } catch {
            fail(error)
        }
    }

    func deletePairing() {
        try? FileManager.default.removeItem(at: JITEngine.shared.pairingFileURL())
        refreshPairingState()
        toast = "已移除配对文件"
    }

    // MARK: - VPN

    func probeVPN(completion: ((Bool) -> Void)? = nil) {
        guard !vpnProbing else { return }
        vpnProbing = true
        Task.detached(priority: .utility) {
            let probe = JITEngine.shared.probeLoopback()
            await MainActor.run {
                self.vpnConnected = probe.ok
                self.vpnPort = probe.port
                self.vpnMessage = probe.message
                self.vpnProbing = false
                if probe.ok {
                    self.loadIconsIfNeeded()
                    if self.apps.isEmpty && self.pairingExists && !self.isLoadingApps && !self.didAutoRefresh {
                        self.didAutoRefresh = true
                        self.refreshApps()
                    }
                } else {
                    self.didAutoRefresh = false
                }
                completion?(probe.ok)
            }
        }
    }

    // MARK: - 图标

    private func iconCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadCachedIcons() {
        let dir = iconCacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var loaded: [String: Data] = [:]
        for file in files where file.pathExtension == "png" {
            if let data = try? Data(contentsOf: file) {
                loaded[file.deletingPathExtension().lastPathComponent] = data
            }
        }
        icons = loaded
    }

    func icon(for bundleID: String) -> UIImage? {
        guard let data = icons[bundleID] else { return nil }
        return UIImage(data: data)
    }

    func loadIconsIfNeeded(force: Bool = false) {
        guard pairingExists, vpnConnected else { return }
        guard !iconLoading else { return }
        let missing = apps.filter { icons[$0.bundleID] == nil }.map(\.bundleID)
        guard !missing.isEmpty || force else { return }
        iconLoading = true
        let targets = force ? apps.map(\.bundleID) : missing

        Task.detached(priority: .utility) {
            var fetched: [String: Data] = [:]
            do {
                try JITEngine.shared.fetchIcons(bundleIDs: targets) { bundleID, data in
                    fetched[bundleID] = data
                    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("AppIcons", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? data.write(to: dir.appendingPathComponent("\(bundleID).png"))
                }
            } catch {
                await MainActor.run { self.append("图标加载中断：\(error.localizedDescription)", error: true) }
            }
            await MainActor.run {
                for (bundleID, data) in fetched {
                    self.icons[bundleID] = data
                }
                self.iconLoading = false
                if !fetched.isEmpty {
                    self.append("已加载 \(fetched.count) 个应用图标")
                }
            }
        }
    }

    /// 一键自检：配对文件 + VPN + 隧道 + 权限。
    func runDiagnostics() {
        append("开始自检…")
        guard pairingExists else {
            fail(JITEngineError.pairingMissing)
            return
        }
        do {
            _ = try JITEngine.shared.validatePairingFile()
            append("配对文件解析通过（\(pairingKind.rawValue)）")
        } catch {
            fail(error)
            return
        }
        probeVPN { ok in
            guard ok else {
                self.lastError = "VPN 未开启，隧道不可达"
                self.append("自检失败：VPN 未开启", error: true)
                return
            }
            Task.detached(priority: .userInitiated) {
                do {
                    let tunnel = try JITEngine.shared.createTunnelAuto { line in
                        Task { @MainActor in AppModel.shared.append(line) }
                    }
                    tunnel.close()
                    await MainActor.run {
                        self.append("隧道连接成功，配置完整")
                        self.toast = "自检通过"
                    }
                } catch {
                    await MainActor.run { self.fail(error) }
                }
            }
        }
    }

    // MARK: - 一键操作

    /// 一键补齐配置：校验配对 → 探测 VPN → 拉应用列表 → 预载图标
    func oneTapSetup() {
        guard pairingExists else {
            fail(JITEngineError.pairingMissing)
            return
        }
        append("一键补齐配置：开始")
        probeVPN { ok in
            guard ok else {
                self.lastError = "VPN 未开启，先把 LocalDevVPN 连上"
                self.append("一键补齐失败：VPN 未开启", error: true)
                return
            }
            self.runDiagnostics()
            self.refreshApps(force: true)
            self.loadIconsIfNeeded(force: true)
            self.toast = "配置已补齐"
        }
    }

    /// 批量开 JIT（逐个启动、逐个附加、逐个分离）
    func enableBatch(_ apps: [InstalledApp]) {
        let targets = apps.filter { $0.isJITCapable }
        guard !targets.isEmpty, !batchRunning else { return }
        guard pairingExists else {
            fail(JITEngineError.pairingMissing)
            return
        }
        batchRunning = true
        batchTotal = targets.count
        batchDone = 0
        let activeBundle = sessionBundle
        append("批量开启 JIT：共 \(targets.count) 个应用")

        Task.detached(priority: .userInitiated) {
            var okCount = 0
            for app in targets {
                if app.bundleID == activeBundle {
                    await MainActor.run { self.batchDone += 1 }
                    okCount += 1
                    continue
                }
                await MainActor.run {
                    self.busyBundle = app.bundleID
                    self.append(">>> 批量开启：\(app.name)")
                }
                do {
                    try JITEngine.shared.enableJIT(bundleID: app.bundleID) { line in
                        Task { @MainActor in AppModel.shared.append(line) }
                    }
                    okCount += 1
                } catch {
                    await MainActor.run {
                        self.append("失败：\(app.name) — \(error.localizedDescription)", error: true)
                    }
                }
                await MainActor.run {
                    self.batchDone += 1
                    self.busyBundle = nil
                }
            }
            await MainActor.run {
                self.batchRunning = false
                self.busyBundle = nil
                self.toast = "批量完成 \(okCount)/\(targets.count)"
                self.append("批量开启结束：成功 \(okCount)/\(targets.count)")
            }
        }
    }

    /// 把配对文件导出到「文件」App，其他 JIT 启动器可以直接拿去导入
    @discardableResult
    func exportPairingForOtherLaunchers() -> URL? {
        let source = JITEngine.shared.pairingFileURL()
        guard FileManager.default.fileExists(atPath: source.path) else {
            lastError = JITEngineError.pairingMissing.localizedDescription
            return nil
        }
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dir = documents.appendingPathComponent("Export", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = dir.appendingPathComponent("JITRPOQ-pairing.plist")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            toast = "已导出到 文件 App › JIT RPOQ › Export"
            append("配对文件已导出：\(destination.lastPathComponent)")
            return destination
        } catch {
            fail(error)
            return nil
        }
    }

    // MARK: - 签名（Apple ID 证书 / 描述文件）

    func importProfile(from url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            let data = try Data(contentsOf: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            let parsed = try ProfileInspector.parse(data: data)
            profile = parsed
            profileFileName = url.lastPathComponent
            profileRawData = data
            identityMatchesProfile = identityCertDER.map { ProfileInspector.certificate($0, matches: parsed) } ?? false
            let jit = parsed.isJITCapable ? "包含 get-task-allow（可开 JIT）" : "不含 get-task-allow（签出来的 App 不能开 JIT）"
            append("描述文件已读取：\(parsed.name)，\(jit)")
            toast = parsed.isJITCapable ? "描述文件支持 JIT" : "描述文件不含 JIT 权限"
        } catch {
            fail(error)
        }
    }

    func importP12(from url: URL, password: String) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            let data = try Data(contentsOf: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            let result = try ProfileInspector.importP12(data: data, password: password)
            identitySubject = result.subject
            identityCertDER = result.certificateDER
            identityP12Data = data
            if let profile {
                identityMatchesProfile = ProfileInspector.certificate(result.certificateDER, matches: profile)
            }
            append("证书已导入：\(result.subject)")
            toast = "证书已导入"
        } catch {
            fail(error)
        }
    }

    // MARK: - Apple ID 云签名

    func startCloudSign(appleID: String, password: String, certPassword: String,
                        pat: String, teamID: String, bundleID: String) {
        guard !cloudRunning else { return }
        let trimmedID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !password.isEmpty else {
            lastError = "先填 Apple ID 和 App 专用密码"
            return
        }
        guard !pat.isEmpty else {
            lastError = "需要 GitHub PAT（repo + admin 权限），用来写入 Secrets 并触发流水线"
            return
        }

        Keychain.set(trimmedID, for: "APPLE_ID")
        Keychain.set(password, for: "APPLE_PASSWORD")
        Keychain.set(pat, for: "GITHUB_PAT")
        if !certPassword.isEmpty { Keychain.set(certPassword, for: "CERT_PASSWORD") }

        cloudRunning = true
        cloudStatus = "写入证书信息…"
        append("云签名开始：\(trimmedID)")

        Task.detached(priority: .userInitiated) {
            do {
                try await CloudSigner.setSecret(name: "APPLE_ID", value: trimmedID, token: pat)
                try await CloudSigner.setSecret(name: "APPLE_PASSWORD", value: password, token: pat)
                if !certPassword.isEmpty {
                    try await CloudSigner.setSecret(name: "CERT_PASSWORD", value: certPassword, token: pat)
                }
                if !teamID.isEmpty {
                    try await CloudSigner.setSecret(name: "TEAM_ID", value: teamID, token: pat)
                }

                await MainActor.run { self.cloudStatus = "触发云端签名…" }
                try await CloudSigner.dispatch(bundleID: bundleID, teamID: teamID, token: pat)
                await MainActor.run { self.cloudStatus = "云端排队中…" }

                for _ in 0..<80 {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    if let run = try await CloudSigner.latestRun(token: pat) {
                        await MainActor.run {
                            self.cloudRunURL = run.htmlURL
                            if run.status == "completed" {
                                let ok = run.conclusion == "success"
                                self.cloudStatus = ok ? "签名完成，去下载" : "失败：\(run.conclusion ?? "unknown")"
                            } else {
                                self.cloudStatus = run.status == "queued" ? "排队中" : "正在签名"
                            }
                        }
                        if run.status == "completed" { break }
                    }
                }
                await MainActor.run { self.cloudRunning = false }
            } catch {
                await MainActor.run {
                    self.cloudRunning = false
                    self.cloudStatus = "失败"
                    self.fail(error)
                }
            }
        }
    }

    /// 导出描述文件 + 证书到「文件」App › JIT RPOQ › Export
    @discardableResult
    func exportSigningAssets() -> [URL] {
        var written: [URL] = []
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Export", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if let raw = profileRawData {
                let name = (profileFileName?.isEmpty == false) ? profileFileName! : "profile.mobileprovision"
                let dest = dir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                try raw.write(to: dest, options: .atomic)
                written.append(dest)
            }
            if let p12 = identityP12Data {
                let dest = dir.appendingPathComponent("AppleID-signing.p12")
                try? FileManager.default.removeItem(at: dest)
                try p12.write(to: dest, options: .atomic)
                written.append(dest)
            }
            if written.isEmpty {
                lastError = "还没有导入描述文件或证书"
                return []
            }
            toast = "已导出 \(written.count) 个文件到 文件 App › JIT RPOQ › Export"
            append("签名文件已导出：\(written.map(\.lastPathComponent).joined(separator: "、"))")
            return written
        } catch {
            fail(error)
            return []
        }
    }

    // MARK: - 应用

    func refreshApps(force: Bool = false) {
        guard pairingExists else {
            lastError = JITEngineError.pairingMissing.localizedDescription
            return
        }
        probeVPN()
        guard vpnConnected || force else {
            lastError = JITEngineError.loopbackUnreachable.localizedDescription
            return
        }
        isLoadingApps = true
        lastError = nil
        append("读取应用列表…")

        Task.detached(priority: .userInitiated) {
            do {
                let list = try JITEngine.shared.fetchApps { line in
                    Task { @MainActor in AppModel.shared.append(line) }
                }
                await MainActor.run {
                    self.apps = list.sorted {
                        if $0.isJITCapable != $1.isJITCapable { return $0.isJITCapable }
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    self.isLoadingApps = false
                    self.append("读取到 \(list.count) 个应用，其中 \(list.filter { $0.isJITCapable }.count) 个可开 JIT")
                }
                await MainActor.run {
                    self.loadIconsIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingApps = false
                    self.fail(error)
                }
            }
        }
    }

    func requestHome() {
        homeRequest = UUID()
    }

    /// iOS 27 无线配对生成的文件：直接导入并提示。
    func importGeneratedPairing(at url: URL, deviceName: String?) {
        importPairing(from: url, kind: .rpp)
        toast = deviceName.map { "配对完成：\($0)" } ?? "配对文件已生成"
    }

    func enable(_ app: InstalledApp, script: String? = nil) {
        guard pairingExists else {
            lastError = JITEngineError.pairingMissing.localizedDescription
            return
        }
        busyBundle = app.bundleID
        lastError = nil
        append(">>> 开启 JIT：\(app.name) [\(app.bundleID)]")

        let useScript = useIOS26Script && script == nil
        let scriptText = script ?? (useScript ? Self.bundledScript : nil)
        let bundleID = app.bundleID
        let name = app.name

        Task.detached(priority: .userInitiated) {
            do {
                if let scriptText, !scriptText.isEmpty {
                    let session = try JITEngine.shared.startSession(bundleID: bundleID, script: scriptText) { line in
                        Task { @MainActor in AppModel.shared.append(line) }
                    }
                    session.onFinish = {
                        Task { @MainActor in
                            if self.sessionBundle == bundleID {
                                self.sessionBundle = nil
                                self.append("JIT 会话已结束：\(name)")
                            }
                        }
                    }
                    await MainActor.run {
                        self.activeSession?.close()
                        self.activeSession = session
                        self.sessionBundle = bundleID
                        self.busyBundle = nil
                        self.lastBundleID = bundleID
                        self.toast = "\(name) 的 JIT 已开启"
                        self.append("JIT 会话运行中：\(name)")
                    }
                } else {
                    try JITEngine.shared.enableJIT(bundleID: bundleID) { line in
                        Task { @MainActor in AppModel.shared.append(line) }
                    }
                    await MainActor.run {
                        self.busyBundle = nil
                        self.lastBundleID = bundleID
                        self.toast = "\(name) 的 JIT 已开启"
                        self.append("JIT 已开启：\(name)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.busyBundle = nil
                    self.fail(error)
                }
            }
        }
    }

    func launchOnly(_ app: InstalledApp) {
        busyBundle = app.bundleID
        Task.detached(priority: .userInitiated) {
            do {
                try JITEngine.shared.launchApp(bundleID: app.bundleID) { line in
                    Task { @MainActor in AppModel.shared.append(line) }
                }
                await MainActor.run {
                    self.busyBundle = nil
                    self.toast = "已启动 \(app.name)"
                }
            } catch {
                await MainActor.run {
                    self.busyBundle = nil
                    self.fail(error)
                }
            }
        }
    }

    func stopSession() {
        activeSession?.close()
        activeSession = nil
        sessionBundle = nil
        toast = "JIT 会话已停止"
    }

    func app(named bundleID: String) -> InstalledApp? {
        apps.first { $0.bundleID == bundleID }
    }

    func toggleFavourite(_ app: InstalledApp) {
        if favourites.contains(app.bundleID) {
            favourites.remove(app.bundleID)
        } else {
            favourites.insert(app.bundleID)
        }
    }

    // MARK: - 脚本

    static var bundledScript: String { loadScript(named: "jit26") ?? "" }

    static func loadScript(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 用脚本给最后使用的应用开 JIT。
    func runScriptOnLastApp() {
        guard let bundleID = lastBundleID, let app = app(named: bundleID) else {
            lastError = "还没有目标应用，先在「应用」页开一次 JIT。"
            return
        }
        enable(app, script: Self.bundledScript)
    }

    // MARK: - 自动开启

    func handleURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "jitrpoq" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let bundle = comps?.queryItems?.first(where: { $0.name == "bundle" || $0.name == "bundleId" })?.value
        let action = url.host?.lowercased() ?? ""

        switch action {
        case "enable", "auto":
            guard let bundle else {
                lastError = "链接缺少 bundle 参数"
                return
            }
            pendingAutoBundle = bundle
            append("收到自动开启请求：\(bundle)")
            if !apps.isEmpty, let app = app(named: bundle) {
                enable(app)
                pendingAutoBundle = nil
            } else {
                refreshApps()
            }
        case "launch":
            if let bundle, let app = app(named: bundle) {
                launchOnly(app)
            } else {
                refreshApps()
            }
        case "importpairing":
            toast = "请点「导入配对文件」"
        default:
            break
        }
    }

    /// 应用列表刷新完成后，处理挂起的自动开启请求。
    func consumePendingAuto() {
        guard let bundle = pendingAutoBundle, let app = app(named: bundle) else { return }
        pendingAutoBundle = nil
        enable(app)
    }
}
