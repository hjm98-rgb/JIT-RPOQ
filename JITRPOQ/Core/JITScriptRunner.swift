//
//  JITScriptRunner.swift
//  JIT RPOQ
//
//  脚本引擎：JavaScriptCore + debugserver 桥。
//  脚本里可以用：log()、send_command()、prepare_memory_region()、get_pid()。
//

import Foundation
import JavaScriptCore
import idevice

enum JITScriptError: LocalizedError {
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case .runtime(let text): return text
        }
    }
}

final class JITScriptRunner {
    private var context: JSContext?
    private var proxy: OpaquePointer?
    private var logHandler: ((String) -> Void)?

    func run(script: String, pid: Int32, proxy: OpaquePointer, log: @escaping (String) -> Void) throws -> String {
        self.proxy = proxy
        self.logHandler = log

        let ctx = JSContext()!
        self.context = ctx

        let getPid: @convention(block) () -> Int32 = { pid }
        let sendCommand: @convention(block) (String?) -> String = { [weak self] command in
            guard let self, let command else { return "" }
            return self.send(command)
        }
        let prepareRegion: @convention(block) (UInt64, UInt64) -> String = { [weak self] address, size in
            guard let self else { return "" }
            do {
                try self.prepareRegion(start: address, size: size)
                return "OK"
            } catch {
                self.logHandler?("内存标记失败：\(error.localizedDescription)")
                return ""
            }
        }
        let logFunction: @convention(block) (String) -> Void = { [weak self] line in
            self?.logHandler?(line)
        }
        let sleepFunction: @convention(block) (Double) -> Void = { seconds in
            Thread.sleep(forTimeInterval: max(0, seconds))
        }
        let hasTXM: @convention(block) () -> Bool = {
            // A12 / A13 等无 TXM；A14 之后有 TXM。这里只做提示，不影响流程。
            return false
        }

        ctx.setObject(getPid, forKeyedSubscript: "get_pid" as NSString)
        ctx.setObject(sendCommand, forKeyedSubscript: "send_command" as NSString)
        ctx.setObject(prepareRegion, forKeyedSubscript: "prepare_memory_region" as NSString)
        ctx.setObject(logFunction, forKeyedSubscript: "log" as NSString)
        ctx.setObject(sleepFunction, forKeyedSubscript: "sleep_ms" as NSString)
        ctx.setObject(hasTXM, forKeyedSubscript: "hasTXM" as NSString)

        ctx.exception = nil
        ctx.evaluateScript(script)

        if let exception = ctx.exception {
            let message = exception.toString() ?? "脚本执行失败"
            throw JITScriptError.runtime(message)
        }
        return "脚本执行完成"
    }

    private func send(_ command: String) -> String {
        guard let proxy else { return "" }
        guard let handle = debugserver_command_new(command, nil, 0) else { return "" }
        var response: UnsafeMutablePointer<CChar>?
        let error = debug_proxy_send_command(proxy, handle, &response)
        debugserver_command_free(handle)
        if error != nil {
            if let response { idevice_string_free(response) }
            return ""
        }
        defer { if let response { idevice_string_free(response) } }
        guard let response else { return "" }
        return String(cString: response)
    }

    /// 给 JIT 页批量打上可执行标记：每个 16KB 页写一条 `M<addr>,1:69`。
    private func prepareRegion(start: UInt64, size: UInt64) throws {
        guard size > 0, let proxy else { return }
        let pageSize: UInt64 = 0x4000
        let pageCount = Int((size - 1) / pageSize + 1)
        let commandSize = 19
        var buffer = [UInt8](repeating: 0, count: pageCount * commandSize)

        var address = start
        for index in 0..<pageCount {
            let base = index * commandSize
            buffer[base] = 0x24 // '$'
            buffer[base + 1] = 0x4D // 'M'
            writeAddress(address, into: &buffer, at: base + 2)
            buffer[base + 11] = 0x2C // ','
            buffer[base + 12] = 0x31 // '1'
            buffer[base + 13] = 0x3A // ':'
            buffer[base + 14] = 0x36 // '6'
            buffer[base + 15] = 0x39 // '9'
            buffer[base + 16] = 0x23 // '#'
            let checksum = checksum(of: buffer, from: base + 1, to: base + 16)
            buffer[base + 17] = hexNibble(checksum >> 4)
            buffer[base + 18] = hexNibble(checksum & 0xF)
            address += pageSize
        }

        let batch = 96
        var offset = 0
        while offset < pageCount {
            let count = min(batch, pageCount - offset)
            let byteOffset = offset * commandSize
            let byteCount = count * commandSize
            let error = buffer.withUnsafeBytes { raw -> UnsafeMutablePointer<IdeviceFfiError>? in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                return debug_proxy_send_raw(proxy, base.advanced(by: byteOffset), UInt(byteCount))
            }
            if let error {
                let message = error.pointee.message.map { String(cString: $0) } ?? "内存标记失败"
                idevice_error_free(error)
                throw JITScriptError.runtime(message)
            }
            for _ in 0..<count {
                var response: UnsafeMutablePointer<CChar>?
                let readError = debug_proxy_read_response(proxy, &response)
                if let response { idevice_string_free(response) }
                if let readError {
                    let message = readError.pointee.message.map { String(cString: $0) } ?? "内存标记无响应"
                    idevice_error_free(readError)
                    throw JITScriptError.runtime(message)
                }
            }
            offset += count
        }
    }

    private func writeAddress(_ address: UInt64, into buffer: inout [UInt8], at index: Int) {
        let hexDigits = Array(String(format: "%016llx", address))
        // debugserver 的地址是 8 位十六进制、按半字节填充，这里取低 8 位并前补 0
        let low8 = Array(hexDigits.suffix(8))
        for (offset, character) in low8.enumerated() {
            buffer[index + offset] = character.asciiValue ?? 0x30
        }
    }

    private func checksum(of buffer: [UInt8], from start: Int, to end: Int) -> UInt8 {
        var sum: UInt32 = 0
        for index in start...end {
            sum += UInt32(buffer[index])
        }
        return UInt8(sum % 256)
    }

    private func hexChar(_ value: UInt8) -> String {
        return String(format: "%x", value)
    }

    private func hexNibble(_ value: UInt8) -> UInt8 {
        return value < 10 ? 0x30 + value : 0x61 + (value - 10)
    }
}
