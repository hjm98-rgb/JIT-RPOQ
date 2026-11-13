//
//  WirelessPairing.swift
//  JIT RPOQ
//
//  iOS 27 的「设备端无线配对」：本机扮演一台局域网里的电脑。
//  流程与 StikPair 一致：
//    pairable_host_prepare → 自己监听 TCP → 用 NetService 广播
//    _remotepairing-pairable-host._tcp → 设备连上来 → pairable_host_accept_fd
//

import Foundation
import Network
import AVFoundation
import idevice

private final class PinBox {
    let handler: (String) -> Void
    init(_ handler: @escaping (String) -> Void) { self.handler = handler }
}

private func jitPairingPinTrampoline(_ pin: UnsafePointer<CChar>?, _ context: UnsafeMutableRawPointer?) {
    guard let pin, let context else { return }
    let box = Unmanaged<PinBox>.fromOpaque(context).takeUnretainedValue()
    box.handler(String(cString: pin))
}

final class WirelessPairingHost: NSObject, NetServiceDelegate {
    struct Result {
        let url: URL
        let deviceName: String?
        let deviceModel: String?
        let udid: String?
    }

    private var hostHandle: OpaquePointer?
    private var service: NetService?
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var stopped = false
    private var finished = false
    private var port: UInt16 = 0

    private let log: (String) -> Void
    private let onPin: (String) -> Void
    private let completion: (Swift.Result<Result, Error>) -> Void

    init(log: @escaping (String) -> Void,
         onPin: @escaping (String) -> Void,
         completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        self.log = log
        self.onPin = onPin
        self.completion = completion
    }

    // MARK: - 启动

    func start(name: String = "JIT RPOQ", model: String = "Mac17,7") throws {
        var handle: OpaquePointer?
        var serviceIDPointer: UnsafeMutablePointer<CChar>?
        var txtPointer: UnsafeMutablePointer<UInt8>?
        var txtLength: UInt = 0

        let error = name.withCString { hostname in
            model.withCString { modelName in
                pairable_host_prepare(hostname, modelName, false, &handle, &serviceIDPointer, &txtPointer, &txtLength, nil)
            }
        }
        if let error {
            log("生成主机身份失败：\(describe(error))")
            throw JITEngineError.message("生成主机身份失败，请重试")
        }
        guard let handle else { throw JITEngineError.message("主机身份句柄为空") }
        hostHandle = handle

        let serviceID = serviceIDPointer.map { String(cString: $0) } ?? name
        if let serviceIDPointer { idevice_string_free(serviceIDPointer) }

        var txt: [String: Data] = [:]
        if let txtPointer, txtLength > 0 {
            let data = Data(bytes: txtPointer, count: txtLength)
            idevice_data_free(txtPointer, txtLength)
            txt = Self.parseTXT(data)
        }
        log("主机身份已生成：\(serviceID)")

        listenFD = try makeListener()
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listenFD, $0, &length)
            }
        }
        port = addr.sin_port.bigEndian
        guard port > 0 else {
            closeListener()
            throw JITEngineError.message("监听端口分配失败")
        }
        log("本地端口已监听：\(port)")

        let netService = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: Int32(port)
        )
        netService.delegate = self
        if !txt.isEmpty {
            netService.setTXTRecord(NetService.data(fromTXTRecord: txt))
        }
        netService.schedule(in: .main, forMode: .common)
        netService.publish()
        service = netService
        log("已广播配对服务，等待设备在开发者模式里发起配对")

        let worker = Thread { [weak self] in
            self?.acceptLoop()
        }
        worker.name = "com.rpoq.wirelesspairing"
        worker.start()
    }

    private static func parseTXT(_ data: Data) -> [String: Data] {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = object as? [String: Any] else {
            return [:]
        }
        var result: [String: Data] = [:]
        for (key, value) in dict {
            if let string = value as? String {
                result[key] = Data(string.utf8)
            } else if let value = value as? Data {
                result[key] = value
            } else {
                result[key] = Data("\(value)".utf8)
            }
        }
        return result
    }

    private func makeListener() throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw JITEngineError.message("无法创建监听 socket") }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            throw JITEngineError.message("监听端口绑定失败")
        }
        guard listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw JITEngineError.message("监听端口失败")
        }
        return descriptor
    }

    // MARK: - 接受连接

    private func acceptLoop() {
        var addr = sockaddr()
        var length = socklen_t(MemoryLayout<sockaddr>.size)
        let clientFD = withUnsafeMutablePointer(to: &addr) { pointer in
            accept(listenFD, pointer, &length)
        }
        guard clientFD >= 0 else {
            log("监听已关闭")
            return
        }
        log("设备已连接，开始 pair-setup")
        performPairing(fd: clientFD)
        Darwin.close(clientFD)
    }

    private func performPairing(fd: Int32) {
        guard let hostHandle else { return }
        let box = PinBox(onPin)
        var pairingFile: OpaquePointer?
        var peer: OpaquePointer?

        let error = pairable_host_accept_fd(hostHandle, fd, jitPairingPinTrampoline,
                                            Unmanaged.passUnretained(box).toOpaque(),
                                            &peer, &pairingFile)

        if let error {
            log("配对失败：\(describe(error))")
            finish(.failure(JITEngineError.message("配对失败，请重新开始")))
            return
        }
        guard let pairingFile else {
            finish(.failure(JITEngineError.message("配对文件为空")))
            return
        }
        defer { rp_pairing_file_free(pairingFile) }

        let destination = JITEngine.shared.pairingFileURL()
        let writeError = destination.path.withCString { path in
            rp_pairing_file_write(pairingFile, path)
        }
        if let writeError {
            log("写入配对文件失败：\(describe(writeError))")
            finish(.failure(JITEngineError.message("写入配对文件失败")))
            return
        }

        var deviceName: String?
        var deviceModel: String?
        var udid: String?
        if let peer {
            let info = peer.assumingMemoryBound(to: RpPairingPeerDeviceC.self).pointee
            if let name = info.name { deviceName = String(cString: name) }
            if let model = info.model { deviceModel = String(cString: model) }
            if let identifier = info.udid { udid = String(cString: identifier) }
            rppairing_peer_device_free(peer)
        }

        log("配对完成，配对文件已保存：\(destination.lastPathComponent)")
        finish(.success(Result(url: destination, deviceName: deviceName, deviceModel: deviceModel, udid: udid)))
    }

    private func describe(_ error: UnsafeMutablePointer<IdeviceFfiError>?) -> String {
        guard let error else { return "未知错误" }
        defer { idevice_error_free(error) }
        if let message = error.pointee.message {
            return String(cString: message)
        }
        return "错误码 \(error.pointee.code)"
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        completion(result)
    }

    // MARK: - 停止

    func stop() {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        stopped = true
        lock.unlock()

        service?.stop()
        service?.delegate = nil
        service = nil
        closeListener()

        if let hostHandle {
            pairable_host_free(hostHandle)
            self.hostHandle = nil
        }
        log("配对服务已停止")
    }

    private func closeListener() {
        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
            Darwin.close(listenFD)
            listenFD = -1
        }
    }

    // MARK: - NetServiceDelegate

    func netServiceDidPublish(_ sender: NetService) {
        log("Bonjour 服务已发布：\(sender.name)（端口 \(port)）")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        log("Bonjour 发布失败：\(errorDict)")
    }
}

// MARK: - 局域网权限探测

/// 用一个临时 Bonjour 探测触发系统的「本地网络」授权弹窗。
final class LocalNetworkPermission: NSObject {
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Bool, Never>?

    func request(timeout: TimeInterval = 45) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let params = NWParameters.tcp
            params.includePeerToPeer = true

            let listener = try? NWListener(using: params)
            listener?.service = NWListener.Service(name: "JITRPOQProbe", type: "_jitprobe._tcp")
            listener?.newConnectionHandler = { $0.cancel() }
            self.listener = listener

            let browser = NWBrowser(for: .bonjour(type: "_jitprobe._tcp", domain: nil), using: params)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                if !results.isEmpty { self?.finish(true) }
            }
            self.browser = browser

            listener?.start(queue: .main)
            browser.start(queue: .main)

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(false)
            }
        }
    }

    private func finish(_ authorized: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: authorized)
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
    }
}

// MARK: - 后台保活（静音音频）

/// 配对时用户要离开应用去「设置」，用静音循环音频把进程保活。
final class PairingKeepAlive {
    static let shared = PairingKeepAlive()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var running = false

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = engine.outputNode.inputFormat(forBus: 0)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            let frames = AVAudioFrameCount(format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames

            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        running = false
    }
}
