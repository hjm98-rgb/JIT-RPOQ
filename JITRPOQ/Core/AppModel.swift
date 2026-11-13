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

    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var skyAnimation: Bool {
        didSet { UserDefaults.standard.set(skyAnimation, forKey: "skyAnimation") }
    }

    @Published var sessionBundle: String?
    @Published var homeRequest = UUID()
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
        language = UserDefaults.standard.string(forKey: "language") ?? AppLanguage.zh.rawValue
        skyAnimation = UserDefaults.standard.object(forKey: "skyAnimation") as? Bool ?? true
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

    /// 打开作者仓库（系统浏览器）
    func openRepository() {
        guard let url = URL(string: "https://github.com/hjm98-rgb/JIT-RPOQ") else { return }
        UIApplication.shared.open(url)
    }

    /// 清空图标缓存
    func clearIconCache() {
        let dir = iconCacheDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        icons = [:]
        toast = L10n.t("settings.cacheDone", language)
        append("图标缓存已清理")
    }

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

            let detected = kind ?? Self.detectKind(at: destination)
            if detected == .classic {
                throw JITEngineError.pairingInvalid("这是经典配对记录（只有 X.509 证书链），iOS 26 的隧道只认 RPP 配对文件（必须含 public_key / private_key / identifier）。请用「一键生成配对文件」或导出 RPP 格式的文件。")
            }
            _ = try JITEngine.shared.validatePairingFile(at: destination)
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
        // 判定依据只有一个：有没有 RPP 的 Ed25519 钥匙对。
        // iOS 26 的隧道（tunnel_create_rppairing）只认 RPP 文件，
        // 纯 X.509 证书链的经典配对记录即使有 UDID 也喂不进去。
        if dict["public_key"] != nil, dict["private_key"] != nil {
            return .rpp
        }
        return .classic
    }

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

    /// 用原版 LocalDevVPN 的 enable 链接：它会自动连接，连上后按 scheme 回跳本 App。
    func openLocalDevVPN() {
        guard let url = URL(string: "localdevvpn://enable?scheme=jitrpoq") else { return }
        append("正在打开 LocalDevVPN 并自动连接…")
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.append("没打开 LocalDevVPN，跳 App Store", error: true)
                if let store = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044") {
                    UIApplication.shared.open(store)
                }
            }
        }
    }

    func handleURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "jitrpoq" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let bundle = comps?.queryItems?.first(where: { $0.name == "bundle" || $0.name == "bundleId" })?.value
        let action = url.host?.lowercased() ?? ""

        switch action {
        case "", "vpn":
            append("已回到 JIT RPOQ，重新检测 VPN")
            probeVPN()
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
        case "vpn":
            append("LocalDevVPN 已连上，重新检测")
            probeVPN()
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
