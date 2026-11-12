//
//  JITEngine.swift
//  JIT RPOQ
//
//  RemotePairing + debugserver JIT 引擎。基于 idevice 的 C FFI。
//

import Foundation
import Darwin
import idevice

enum JITEngineError: LocalizedError {
    case pairingMissing
    case pairingInvalid(String)
    case loopbackUnreachable
    case ffi(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .pairingMissing:
            return "还没有导入配对文件。请先在「配对」页导入配对文件。"
        case .pairingInvalid(let detail):
            return "配对文件无法解析：\(detail)"
        case .loopbackUnreachable:
            return "连不上 10.7.0.1:49152。请先打开 LocalDevVPN 并连接 VPN（iOS 26 必须）。"
        case .ffi(let detail):
            return detail
        case .message(let text):
            return text
        }
    }
}

/// 一条从 installation_proxy 拿到的应用记录。
struct InstalledApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let version: String
    let isJITCapable: Bool
    let isSystem: Bool
    let path: String

    var id: String { bundleID }
}

/// RPP 隧道句柄。
final class DeviceTunnel {
    var adapter: OpaquePointer?
    var handshake: OpaquePointer?
    var port: UInt16 = JITEngine.remotePairingPort

    func close() {
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    deinit { close() }
}

final class JITEngine {
    static let shared = JITEngine()

    /// LocalDevVPN 建出来的本机回环地址。
    static let targetIP = "10.7.0.1"
    /// RemotePairing 服务端口。
    static let remotePairingPort: UInt16 = 49152
    /// 备用端口（不同系统版本会变）。
    static let fallbackPorts: [UInt16] = [49152, 49153, 62078]

    private let logLock = NSLock()
    private var logSink: ((String) -> Void)?

    private init() {
        var path = (NSTemporaryDirectory() + "rpoq-idevice.log").utf8CString
        _ = path.withUnsafeMutableBufferPointer { buffer in
            idevice_init_logger(IdeviceLogLevel.Info, IdeviceLogLevel.Info, buffer.baseAddress)
        }
    }

    func setLogSink(_ sink: ((String) -> Void)?) {
        logLock.lock()
        logSink = sink
        logLock.unlock()
    }

    func emit(_ line: String) {
        logLock.lock()
        let sink = logSink
        logLock.unlock()
        sink?(line)
    }

    // MARK: - 错误转换

    func consume(_ error: UnsafeMutablePointer<IdeviceFfiError>?, fallback: String) -> JITEngineError {
        guard let error else { return .ffi(fallback) }
        let detail = error.pointee.message.map { String(cString: $0) } ?? fallback
        let code = error.pointee.code
        idevice_error_free(error)
        return .ffi("\(fallback) (code \(code)): \(detail)")
    }

    private func string(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }

    // MARK: - 回环 VPN 检测

    /// 检测 10.7.0.1:49152 是否可以建立 TCP 连接（也就是 LocalDevVPN 是否在工作）。
    func probeLoopback(timeout: TimeInterval = 1.5) -> (ok: Bool, port: UInt16?, message: String) {
        for port in Self.fallbackPorts {
            if let message = tcpProbe(ip: Self.targetIP, port: port, timeout: timeout) {
                return (true, port, message)
            }
        }
        return (false, nil, "10.7.0.1:49152 不可达")
    }

    private func tcpProbe(ip: String, port: UInt16, timeout: TimeInterval) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return nil }

        var flags = fcntl(fd, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 { return "已连接 \(ip):\(port)" }
        guard errno == EINPROGRESS else { return nil }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let waitMs = Int32(timeout * 1000)
        let pollResult = poll(&pfd, 1, waitMs)
        guard pollResult > 0 else { return nil }

        var soError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
        guard soError == 0 else { return nil }
        return "已连接 \(ip):\(port)"
    }

    // MARK: - 配对文件

    func pairingFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pairing.mobiledevicepairing")
    }

    func hasPairingFile() -> Bool {
        FileManager.default.fileExists(atPath: pairingFileURL().path)
    }

    /// 校验配对文件能否被 libidevice 解析。
    func validatePairingFile(at url: URL? = nil) throws -> String {
        let target = url ?? pairingFileURL()
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw JITEngineError.pairingMissing
        }
        var handle: OpaquePointer?
        let error = target.path.withCString { rp_pairing_file_read($0, &handle) }
        if let error {
            throw consume(error, fallback: "配对文件读取失败")
        }
        guard let handle else {
            throw JITEngineError.pairingInvalid("句柄为空")
        }
        rp_pairing_file_free(handle)
        return "配对文件有效"
    }

    /// 读取配对 plist 的元信息（设备 UDID / 是否含证书链）。
    func pairingMetadata(at url: URL) -> [String: String] {
        var info: [String: String] = [:]
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            return info
        }
        if let udid = dict["UDID"] as? String { info["UDID"] = udid }
        if let name = dict["DeviceName"] as? String { info["DeviceName"] = name }
        info["HasHostCert"] = dict["HostCertificate"] != nil ? "1" : "0"
        info["HasDeviceCert"] = dict["DeviceCertificate"] != nil ? "1" : "0"
        info["HasRootCert"] = dict["RootCertificate"] != nil ? "1" : "0"
        if let wifi = dict["WiFiMACAddress"] as? String { info["WiFiMAC"] = wifi }
        return info
    }

    // MARK: - 隧道

    private func openPairingHandle() throws -> OpaquePointer {
        guard hasPairingFile() else { throw JITEngineError.pairingMissing }
        var handle: OpaquePointer?
        let error = pairingFileURL().path.withCString { rp_pairing_file_read($0, &handle) }
        if let error { throw consume(error, fallback: "配对文件读取失败") }
        guard let handle else { throw JITEngineError.pairingMissing }
        return handle
    }

    func createTunnel(hostname: String = "JIT-RPOQ", port: UInt16? = nil) throws -> DeviceTunnel {
        let pairing = try openPairingHandle()
        defer { rp_pairing_file_free(pairing) }

        let usePort = port ?? Self.remotePairingPort
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = usePort.bigEndian
        guard inet_pton(AF_INET, Self.targetIP, &addr.sin_addr) == 1 else {
            throw JITEngineError.message("无法解析回环地址 \(Self.targetIP)")
        }

        let tunnel = DeviceTunnel()
        tunnel.port = usePort

        let error = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                tunnel_create_rppairing(
                    sa,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    hostname,
                    pairing,
                    nil,
                    nil,
                    &tunnel.adapter,
                    &tunnel.handshake
                )
            }
        }

        if let error {
            tunnel.close()
            throw consume(error, fallback: "RPP 隧道建立失败（确认 LocalDevVPN 已连接）")
        }
        guard tunnel.adapter != nil, tunnel.handshake != nil else {
            tunnel.close()
            throw JITEngineError.message("RPP 隧道句柄为空")
        }
        return tunnel
    }

    /// 自动找可用端口建立隧道。
    func createTunnelAuto(hostname: String = "JIT-RPOQ", log: ((String) -> Void)? = nil) throws -> DeviceTunnel {
        var lastError: Error = JITEngineError.loopbackUnreachable
        let probe = probeLoopback()
        let ports = [probe.port].compactMap { $0 } + Self.fallbackPorts
        for port in Array(Set(ports)).sorted() {
            do {
                let tunnel = try createTunnel(hostname: hostname, port: port)
                log?("隧道已建立：\(Self.targetIP):\(port)")
                return tunnel
            } catch {
                lastError = error
                log?("端口 \(port) 连接失败：\(error.localizedDescription)")
            }
        }
        throw lastError
    }

    // MARK: - 应用列表

    func fetchApps(log: ((String) -> Void)? = nil) throws -> [InstalledApp] {
        let tunnel = try createTunnelAuto(log: log)
        defer { tunnel.close() }

        var client: OpaquePointer?
        let connectError = installation_proxy_connect_rsd(tunnel.adapter, tunnel.handshake, &client)
        if let connectError { throw consume(connectError, fallback: "安装服务连接失败") }
        guard let client else { throw JITEngineError.message("安装服务句柄为空") }
        defer { installation_proxy_client_free(client) }

        var raw: UnsafeMutableRawPointer?
        var count = 0
        let error = installation_proxy_get_apps(client, nil, nil, 0, &raw, &count)
        if let error { throw consume(error, fallback: "读取应用列表失败") }
        guard let raw, count > 0 else { return [] }

        let apps = raw.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
        defer {
            for index in 0..<count {
                plist_free(apps[index])
            }
            idevice_data_free(
                raw.assumingMemoryBound(to: UInt8.self),
                UInt(count * MemoryLayout<UnsafeMutableRawPointer?>.stride)
            )
        }

        var result: [InstalledApp] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let plist = apps[index] else { continue }
            var bin: UnsafeMutablePointer<CChar>?
            var binLength: UInt32 = 0
            guard plist_to_bin(plist, &bin, &binLength) == PLIST_ERR_SUCCESS, let bin, binLength > 0 else { continue }
            let data = Data(bytes: bin, count: Int(binLength))
            plist_mem_free(bin)
            guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = object as? [String: Any] else { continue }
            result.append(Self.makeApp(from: dict))
        }
        return result
    }

    private static func makeApp(from dict: [String: Any]) -> InstalledApp {
        let bundleID = dict["CFBundleIdentifier"] as? String ?? "unknown"
        let display = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String) ?? bundleID
        let version = (dict["CFBundleShortVersionString"] as? String) ?? ""
        let type = dict["ApplicationType"] as? String ?? ""
        let isSystem = (type == "System" || type == "HiddenSystemApp")
        let jit = Self.getTaskAllow(dict)
        return InstalledApp(
            bundleID: bundleID,
            name: display,
            version: version,
            isJITCapable: jit,
            isSystem: isSystem,
            path: dict["Path"] as? String ?? ""
        )
    }

    private static func getTaskAllow(_ dict: [String: Any]) -> Bool {
        guard let entitlements = dict["Entitlements"] as? [String: Any] else { return false }
        if let value = entitlements["get-task-allow"] as? Bool { return value }
        if let value = entitlements["get-task-allow"] as? NSNumber { return value.boolValue }
        return false
    }

    // MARK: - 开 JIT

    /// 直接开 JIT：带调试启动 → 附加 debugserver → 分离。
    /// 传入 script 时用脚本模式（iOS 26 的 JIT page 协议）。
    @discardableResult
    func enableJIT(bundleID: String, script: String? = nil, log: @escaping (String) -> Void) throws -> Int32 {
        let tunnel = try createTunnelAuto(hostname: "JITRPOQ", log: log)
        defer { tunnel.close() }

        var remoteServer: OpaquePointer?
        let rsError = remote_server_connect_rsd(tunnel.adapter, tunnel.handshake, &remoteServer)
        if let rsError { throw consume(rsError, fallback: "远程服务连接失败") }
        guard let remoteServer else { throw JITEngineError.message("远程服务句柄为空") }
        defer { remote_server_free(remoteServer) }

        var processControl: OpaquePointer?
        let pcError = process_control_new(remoteServer, &processControl)
        if let pcError { throw consume(pcError, fallback: "进程控制打开失败") }
        guard let processControl else { throw JITEngineError.message("进程控制句柄为空") }
        defer { process_control_free(processControl) }

        var pid: UInt64 = 0
        let launchError = bundleID.withCString { bundle in
            process_control_launch_app(processControl, bundle, nil, 0, nil, 0, true, true, &pid)
        }
        if let launchError { throw consume(launchError, fallback: "启动 \(bundleID) 失败") }
        log("已带调试启动 \(bundleID)，PID \(pid)")

        var debugProxy: OpaquePointer?
        let dpError = debug_proxy_connect_rsd(tunnel.adapter, tunnel.handshake, &debugProxy)
        if let dpError { throw consume(dpError, fallback: "debugserver 连接失败") }
        guard let debugProxy else { throw JITEngineError.message("debugserver 句柄为空") }
        defer { debug_proxy_free(debugProxy) }

        _ = debug_proxy_send_ack(debugProxy)
        _ = debug_proxy_send_ack(debugProxy)
        _ = send("QStartNoAckMode", proxy: debugProxy, log: log)
        debug_proxy_set_ack_mode(debugProxy, 0)

        if let script, !script.isEmpty {
            log("使用 iOS 26 脚本模式开启 JIT")
            let runner = JITScriptRunner()
            let output = try runner.run(script: script, pid: Int32(pid), proxy: debugProxy, log: log)
            if !output.isEmpty { log(output) }
        } else {
            let attach = "vAttach;\(String(UInt32(pid), radix: 16))"
            let response = try send(attach, proxy: debugProxy, log: log)
            log("附加结果：\(response)")
            _ = try send("D", proxy: debugProxy, log: log)
            log("已分离，JIT 已开放")
        }

        return Int32(pid)
    }

    @discardableResult
    private func send(_ command: String, proxy: OpaquePointer, log: (String) -> Void) throws -> String {
        guard let handle = debugserver_command_new(command, nil, 0) else {
            throw JITEngineError.message("命令分配失败：\(command)")
        }
        var response: UnsafeMutablePointer<CChar>?
        let error = debug_proxy_send_command(proxy, handle, &response)
        debugserver_command_free(handle)
        if let error {
            if let response { idevice_string_free(response) }
            throw consume(error, fallback: "调试命令失败：\(command)")
        }
        defer { if let response { idevice_string_free(response) } }
        guard let response else { return "" }
        return String(cString: response)
    }

    // MARK: - 其它动作

    /// 只启动，不附加调试。
    func launchApp(bundleID: String, log: @escaping (String) -> Void) throws {
        let tunnel = try createTunnelAuto(log: log)
        defer { tunnel.close() }
        var remoteServer: OpaquePointer?
        if let error = remote_server_connect_rsd(tunnel.adapter, tunnel.handshake, &remoteServer) {
            throw consume(error, fallback: "远程服务连接失败")
        }
        guard let remoteServer else { throw JITEngineError.message("远程服务句柄为空") }
        defer { remote_server_free(remoteServer) }
        var processControl: OpaquePointer?
        if let error = process_control_new(remoteServer, &processControl) {
            throw consume(error, fallback: "进程控制打开失败")
        }
        guard let processControl else { throw JITEngineError.message("进程控制句柄为空") }
        defer { process_control_free(processControl) }
        var pid: UInt64 = 0
        let error = bundleID.withCString { bundle in
            process_control_launch_app(processControl, bundle, nil, 0, nil, 0, false, true, &pid)
        }
        if let error { throw consume(error, fallback: "启动应用失败") }
        log("已启动 \(bundleID)，PID \(pid)")
    }
}
