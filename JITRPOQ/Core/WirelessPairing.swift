//
//  WirelessPairing.swift
//  JIT RPOQ
//
//  iOS 27 的「设备端无线配对」：本机扮演一台局域网里的电脑，
//  通过 Bonjour 广播 _remotepairing-pairable-host._tcp，
//  用户在「设置 › 隐私与安全性 › 开发者模式」里点「与 JIT RPOQ 配对」并输入 6 位码。
//

import Foundation

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
        let udid: String?
    }

    private var hostHandle: OpaquePointer?
    private var service: NetService?
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?
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

        var txtData = Data()
        if let txtPointer, txtLength > 0 {
            txtData = Data(bytes: txtPointer, count: txtLength)
            idevice_data_free(txtPointer, txtLength)
        }
        log("主机身份已生成：\(serviceID)")

        // 本地 TCP 监听，端口交给系统分配
        let descriptor = try makeListener()
        listenFD = descriptor

        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        port = addr.sin_port.bigEndian
        guard port > 0 else {
            closeListener()
            throw JITEngineError.message("监听端口分配失败")
        }
        log("本地端口已监听：\(port)")

        let netService = NetService(
            domain: "local.",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: Int32(port)
        )
        netService.delegate = self
        if !txtData.isEmpty {
            _ = netService.setTXTRecord(txtData)
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
        acceptThread = worker
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
        while true {
            lock.lock()
            let stop = stopped
            lock.unlock()
            if stop { return }

            var clientFD: Int32 = -1
            var addr = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            clientFD = withUnsafeMutablePointer(to: &addr) { pointer in
                accept(listenFD, pointer, &length)
            }
            if clientFD < 0 {
                // 取消时 listenFD 被关闭，accept 会立即失败
                return
            }
            log("设备已连接，开始 pair-setup")
            performPairing(fd: clientFD)
            Darwin.close(clientFD)
            return
        }
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
        var udid: String?
        if let peer {
            let info = peer.assumingMemoryBound(to: RpPairingPeerDeviceC.self).pointee
            if let name = info.name { deviceName = String(cString: name) }
            if let identifier = info.udid { udid = String(cString: identifier) }
            rppairing_peer_device_free(peer)
        }

        log("配对完成，配对文件已保存：\(destination.lastPathComponent)")
        finish(.success(Result(url: destination, deviceName: deviceName, udid: udid)))
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

    private func describe(_ error: UnsafeMutablePointer<IdeviceFfiError>?) -> String {
        guard let error else { return "未知错误" }
        defer { idevice_error_free(error) }
        if let message = error.pointee.message {
            return String(cString: message)
        }
        return "错误码 \(error.pointee.code)"
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
