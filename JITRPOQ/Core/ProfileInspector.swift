//
//  ProfileInspector.swift
//  JIT RPOQ
//
//  mobileprovision 解析：从 CMS 容器里取出内嵌 plist，读 Entitlements.get-task-allow、
//  证书列表、有效期、设备 UDID，用来判断「这个 Apple ID 证书能不能签出带 JIT 权限的 App」。
//

import Foundation
import Security

struct ProvisioningProfile {
    var name: String
    var uuid: String
    var teamName: String
    var teamID: String
    var appIDName: String
    var applicationIdentifier: String
    var expiration: Date
    var creationDate: Date?
    var devices: [String]
    var isJITCapable: Bool
    var certificateDERs: [Data]
    var rawPlist: Data
}

enum ProfileInspector {

    /// 从 CMS 签名块里抠出 plist（不验证签名，只取内容）
    static func plistData(from data: Data) throws -> Data {
        let open = Data("<?xml".utf8)
        let close = Data("</plist>".utf8)
        guard let start = data.range(of: open)?.lowerBound,
              let end = data.range(of: close, in: start..<data.endIndex)?.upperBound else {
            throw JITEngineError.pairingInvalid("不是有效的 mobileprovision 描述文件")
        }
        return data.subdata(in: start..<end)
    }

    static func parse(data: Data) throws -> ProvisioningProfile {
        let plist = try plistData(from: data)
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil),
              let dict = object as? [String: Any] else {
            throw JITEngineError.pairingInvalid("描述文件 plist 解析失败")
        }
        let entitlements = dict["Entitlements"] as? [String: Any] ?? [:]
        let jit = (entitlements["get-task-allow"] as? Bool) ?? false
        let certs = (dict["DeveloperCertificates"] as? [Data]) ?? []

        return ProvisioningProfile(
            name: (dict["Name"] as? String) ?? "未命名描述文件",
            uuid: (dict["UUID"] as? String) ?? "-",
            teamName: (dict["TeamName"] as? String) ?? "-",
            teamID: (dict["TeamIdentifier"] as? [String])?.first ?? "-",
            appIDName: (dict["AppIDName"] as? String) ?? "-",
            applicationIdentifier: (entitlements["application-identifier"] as? String) ?? "-",
            expiration: (dict["ExpirationDate"] as? Date) ?? .distantPast,
            creationDate: dict["CreationDate"] as? Date,
            devices: (dict["ProvisionedDevices"] as? [String]) ?? [],
            isJITCapable: jit,
            certificateDERs: certs,
            rawPlist: plist
        )
    }

    /// 导入 p12，取出身份与证书
    static func importP12(data: Data, password: String) throws -> (identity: SecIdentity, certificateDER: Data, subject: String) {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identityValue = first[kSecImportItemIdentity as String] else {
            throw JITEngineError.pairingInvalid("p12 导入失败（密码错误或文件无效，状态码 \(status)）")
        }
        let identity = identityValue as! SecIdentity
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let cert else {
            throw JITEngineError.pairingInvalid("p12 里没有证书")
        }
        let der = SecCertificateCopyData(cert) as Data
        let subject = (SecCertificateCopySubjectSummary(cert) as String?) ?? "证书"
        return (identity, der, subject)
    }

    /// 证书是否出现在描述文件里（同一张叶子证书）
    static func certificate(_ der: Data, matches profile: ProvisioningProfile) -> Bool {
        profile.certificateDERs.contains { $0 == der }
    }
}
