//
//  UpdateChecker.swift
//  JIT RPOQ
//
//  版本更新：拉 GitHub 仓库里的 update.json，比对版本号，
//  新版走苹果的无线安装协议（itms-services）直接安装。
//

import Foundation
import UIKit

struct AppUpdate: Identifiable, Decodable {
    let version: String
    let notes: String?
    let url: String?
    let page: String?

    var id: String { version }
}

enum UpdateChecker {
    /// 版本信息源：改了推上去，所有装着本 App 的设备下次打开就会收到提示。
    static let feedURL = URL(string: "https://raw.githubusercontent.com/hjm98-rgb/JIT-RPOQ/main/update.json")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func fetch() async throws -> AppUpdate? {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let payload = try JSONDecoder().decode(AppUpdate.self, from: data)
        guard isNewer(payload.version, than: currentVersion) else { return nil }
        return payload
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let localParts = local.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(remoteParts.count, localParts.count)
        for index in 0..<count {
            let left = index < remoteParts.count ? remoteParts[index] : 0
            let right = index < localParts.count ? localParts[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// 打开苹果的无线安装协议。
    @discardableResult
    static func install(_ update: AppUpdate) -> Bool {
        if let raw = update.url, !raw.isEmpty, let url = URL(string: raw) {
            UIApplication.shared.open(url, options: [:]) { ok in
                if !ok, let page = update.page, let fallback = URL(string: page) {
                    UIApplication.shared.open(fallback)
                }
            }
            return true
        }
        if let page = update.page, let url = URL(string: page) {
            UIApplication.shared.open(url)
            return true
        }
        return false
    }
}
