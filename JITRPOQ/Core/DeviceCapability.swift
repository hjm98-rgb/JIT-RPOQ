//
//  DeviceCapability.swift
//  JIT RPOQ
//
//  本机配对能力探测。
//  系统版本号只是提示，真正决定能不能跑的是设备上是否真的存在
//  RemotePairing 的设备端配对符号（pairable_host_prepare 等）。
//

import Foundation

enum DeviceCapability {
    /// 系统版本主版本号
    static var systemMajor: Int {
        Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "0") ?? 0
    }

    /// 系统版本是否 >= iOS 27
    static var isIOS27OrNewer: Bool { systemMajor >= 27 }

    /// 运行时是否真的具备本机配对符号（比版本号更可靠）
    static var hasOnDevicePairingSymbols: Bool {
        guard let handle = dlopen(nil, RTLD_NOW) else { return false }
        defer { dlclose(handle) }
        let names = ["pairable_host_prepare", "pairable_host_accept_fd", "pairable_host_free"]
        for name in names where dlsym(handle, name) == nil {
            return false
        }
        return true
    }

    /// 是否应启用「一键生成配对文件」入口
    static var supportsOnDevicePairing: Bool {
        isIOS27OrNewer || hasOnDevicePairingSymbols
    }

    /// 给界面用的能力描述
    static var pairingSupportSummary: String {
        if hasOnDevicePairingSymbols && !isIOS27OrNewer {
            return "系统版本为 iOS \(UIDevice.current.systemVersion)，但检测到本机配对符号，已启用"
        }
        if isIOS27OrNewer && !hasOnDevicePairingSymbols {
            return "系统版本满足，但未检测到本机配对符号，尝试时可能失败"
        }
        return isIOS27OrNewer ? "本机配对可用" : "仅 iOS 27 及以上支持"
    }
}
