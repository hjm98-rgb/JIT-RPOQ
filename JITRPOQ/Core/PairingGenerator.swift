//
//  PairingGenerator.swift
//  JIT RPOQ
//
//  iOS 27 的本机配对（on-device pairing）：
//  本机假装一台「电脑」，把 pairable-host 服务广播到局域网，
//  用户在 设置 › 隐私与安全性 › 开发者模式 里点「Pair with JIT RPOQ」，
//  输入 App 显示的 6 位配对码，配对完成后直接在本机生成配对文件。
//

import Foundation
import Network
import UIKit
import AVFoundation

final class PairingGenerator {
    enum GenError: LocalizedError {
        case ffi(String)

        var errorDescription: String? {
            switch self {
            case .ffi(let message): return message
            }
        }
    }

    /// 广播出去的服务名，用户在设置里看到的就是「Pair with <这个名字>」。
    static let serviceName = "JIT RPOQ"
    /// iOS 把这个 host 当电脑看，必须用 Mac 机型标识。
    static let hostModel = "Mac17,7"
    static let defaultPort: UInt16 = 49155

    var onPin: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFinish: ((Result<URL, Error>) -> Void)?

    private var cancel: OpaquePointer?
    private var service: NetService?
    private var thread: Thread?
    private var keeper: BackgroundKeeper?
    private var finished = false

    var isRunning: Bool { thread != nil && !finished }

    func start(port: UInt16 = PairingGenerator.defaultPort) {
        guard !isRunning else { return }
        finished = false
        keeper = BackgroundKeeper()
        keeper?.start()

        let cancelToken = pairable_host_cancel_new()
        cancel = cancelToken

        let netService = NetService(
            domain: "local.",
            type: "_remotepairing-pairable-host._tcp.",
            name: Self.serviceName,
            port: Int32(port)
        )
        netService.publish()
        service = netService
        onStatus?("已广播配对服务，等待 iPhone 连接（端口 \(port)）")

        let worker = Thread { [weak self] in
            guard let self else { return }
            var hostIRK = [UInt8](repeating: 0, count: 16)
            var pairingFile: OpaquePointer?

            let error = hostIRK.withUnsafeMutableBufferPointer { buffer -> UnsafeMutablePointer<IdeviceFfiError>? in
                Self.serviceName.withCString { name in
                    Self.hostModel.withCString { model in
                        pairable_host_accept(
                            name,
                            model,
                            port,
                            pairPinCallback,
                            Unmanaged.passUnretained(self).toOpaque(),
                            cancelToken,
                            buffer.baseAddress,
                            nil,
                            &pairingFile
                        )
                    }
                }
            }

            if let error {
                let detail = error.pointee.message.map { String(cString: $0) } ?? "配对失败"
                let code = error.pointee.code
                idevice_error_free(error)
                self.finish(.failure(GenError.ffi("配对失败 (code \(code))：\(detail)")))
                return
            }
            guard let pairingFile else {
                self.finish(.failure(GenError.ffi("配对没有返回配对文件")))
                return
            }
            defer { rp_pairing_file_free(pairingFile) }

            let destination = JITEngine.shared.pairingFileURL()
            let writeError = destination.path.withCString { path in
                rp_pairing_file_write(pairingFile, path)
            }
            if let writeError {
                let detail = writeError.pointee.message.map { String(cString: $0) } ?? "写入失败"
                idevice_error_free(writeError)
                self.finish(.failure(GenError.ffi("配对文件写入失败：\(detail)")))
                return
            }
            self.finish(.success(destination))
        }
        worker.name = "com.rpoq.ondevicepairing"
        worker.start()
        thread = worker
    }

    func cancelPairing() {
        if let cancel {
            pairable_host_cancel_signal(cancel)
        }
        finish(.failure(GenError.ffi("已取消配对")))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        service?.stop()
        service = nil
        keeper?.stop()
        keeper = nil
        thread = nil
        if let cancel {
            pairable_host_cancel_free(cancel)
            self.cancel = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?(result)
        }
    }
}

/// C 回调：把设备上显示的 6 位码回传主线程。
private let pairPinCallback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { pin, context in
    guard let pin, let context else { return }
    let generator = Unmanaged<PairingGenerator>.fromOpaque(context).takeUnretainedValue()
    let code = String(cString: pin)
    DispatchQueue.main.async {
        generator.onPin?(code)
        generator.onStatus?("设备已连接，请在 iPhone 上输入配对码")
    }
}

/// 让 App 在用户跳去「设置」时不被立刻挂起：后台任务 + 静音音频循环。
final class BackgroundKeeper {
    private var player: AVAudioPlayer?
    private var task: UIBackgroundTaskIdentifier = .invalid

    func start() {
        guard player == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            player = try AVAudioPlayer(data: Self.silentWav)
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.play()
        } catch {
            player = nil
        }
        task = UIApplication.shared.beginBackgroundTask(withName: "OnDevicePairing") {}
    }

    func stop() {
        player?.stop()
        player = nil
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }

    /// 1 秒 8kHz 单声道 16bit 全零 PCM 的 WAV。
    private static let silentWav: Data = {
        let sampleRate: UInt32 = 8000
        let samples: UInt32 = sampleRate
        let dataSize = samples * 2
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + dataSize); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(sampleRate); append32(sampleRate * 2); append16(2); append16(16)
        append("data"); append32(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }()
}
