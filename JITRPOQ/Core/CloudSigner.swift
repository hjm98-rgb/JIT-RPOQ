//
//  CloudSigner.swift
//  JIT RPOQ
//
//  在云端 Mac 上用你的 Apple ID 申请开发证书 + 描述文件并重签 IPA。
//  App 只负责：写入仓库 Secrets（libsodium sealed box 加密）、触发 workflow、轮询结果。
//

import Foundation
import Sodium

struct CloudRun {
    var id: Int
    var status: String
    var conclusion: String?
    var htmlURL: String
}

enum CloudSignerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum CloudSigner {
    static let owner = "hjm98-rgb"
    static let repo = "JIT-RPOQ"
    static let workflow = "sign.yml"

    private static func request(_ path: String, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    static func setSecret(name: String, value: String, token: String) async throws {
        var publicKeyRequest = request("/actions/secrets/public-key", token: token)
        publicKeyRequest.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: publicKeyRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudSignerError.message("读取仓库公钥失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），PAT 需要 repo + admin 权限")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyBase64 = json["key"] as? String,
              let keyID = json["key_id"] as? String,
              let publicKey = Data(base64Encoded: keyBase64) else {
            throw CloudSignerError.message("公钥格式异常")
        }

        let sodium = Sodium()
        guard let sealed = sodium.box.seal(message: [UInt8](value.utf8), recipientPublicKey: [UInt8](publicKey)) else {
            throw CloudSignerError.message("libsodium 加密失败")
        }
        let payload: [String: String] = [
            "encrypted_value": Data(sealed).base64EncodedString(),
            "key_id": keyID
        ]

        var put = request("/actions/secrets/\(name)", token: token, method: "PUT")
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        put.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, putResponse) = try await URLSession.shared.data(for: put)
        guard let http = putResponse as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 204 else {
            throw CloudSignerError.message("写入 Secret \(name) 失败（HTTP \((putResponse as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
    }

    static func dispatch(bundleID: String, teamID: String, token: String) async throws {
        var dispatch = request("/actions/workflows/\(workflow)/dispatches", token: token, method: "POST")
        dispatch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var inputs: [String: String] = ["bundle_id": bundleID, "export_p12": "true"]
        if !teamID.isEmpty { inputs["team_id"] = teamID }
        dispatch.httpBody = try JSONSerialization.data(withJSONObject: ["ref": "main", "inputs": inputs])
        let (_, response) = try await URLSession.shared.data(for: dispatch)
        guard let http = response as? HTTPURLResponse, http.statusCode == 204 else {
            throw CloudSignerError.message("触发签名流水线失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
    }

    static func latestRun(token: String) async throws -> CloudRun? {
        var list = request("/actions/workflows/\(workflow)/runs?per_page=1", token: token)
        list.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: list)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]],
              let first = runs.first,
              let id = first["id"] as? Int else {
            return nil
        }
        return CloudRun(
            id: id,
            status: (first["status"] as? String) ?? "unknown",
            conclusion: first["conclusion"] as? String,
            htmlURL: (first["html_url"] as? String) ?? "https://github.com/\(owner)/\(repo)/actions"
        )
    }
}
