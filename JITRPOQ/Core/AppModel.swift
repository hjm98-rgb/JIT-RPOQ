//
//  AppModel.swift
//  JIT RPOQ
//

import Foundation
import Combine
import SwiftUI

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
        refreshPairingState()
        probeVPN()
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

    func importPairing(from url: URL, kind: PairingKind) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count > 100 else {
                throw JITEngineError.pairingInvalid("文件内容太小，可能选错了")
            }
            let destination = JITEngine.shared.pairingFileURL()
            try data.write(to: destination, options: .atomic)
            _ = try JITEngine.shared.validatePairingFile(at: destination)
            UserDefaults.standard.set(kind.rawValue, forKey: "pairingKind")
            refreshPairingState()
            pairingKind = kind
            toast = "配对文件已导入：\(kind.rawValue)"
            append("已导入配对文件 \(url.lastPathComponent)（\(kind.rawValue)）")
        } catch {
            fail(error)
        }
    }

    /// 把剪贴板里的配对 plist 文本存成文件。
    func importPairingFromText(_ text: String, kind: PairingKind) {
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

    func probeVPN() {
        let probe = JITEngine.shared.probeLoopback()
        vpnConnected = probe.ok
        vpnPort = probe.port
        vpnMessage = probe.message
    }

    /// 一键自检：配对文件 + VPN + 隧道 + 权限。
    func runDiagnostics() {
        append("开始自检…")
        probeVPN()
        guard pairingExists else {
            fail(JITEngineError.pairingMissing)
            return
        }
        do {
            _ = try JITEngine.shared.validatePairingFile()
            append("配对文件解析通过（\(pairingKind.rawValue)）")
            guard vpnConnected else {
                throw JITEngineError.loopbackUnreachable
            }
            let tunnel = try JITEngine.shared.createTunnelAuto { [weak self] line in
                Task { @MainActor in self?.append(line) }
            }
            tunnel.close()
            append("隧道连接成功，配置完整")
            toast = "自检通过"
        } catch {
            fail(error)
        }
    }

    // MARK: - 应用

    func refreshApps() {
        guard pairingExists else {
            lastError = JITEngineError.pairingMissing.localizedDescription
            return
        }
        probeVPN()
        guard vpnConnected else {
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
            } catch {
                await MainActor.run {
                    self.isLoadingApps = false
                    self.fail(error)
                }
            }
        }
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
