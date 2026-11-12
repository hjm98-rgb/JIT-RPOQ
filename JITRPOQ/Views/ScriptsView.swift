//
//  ScriptsView.swift
//  JIT RPOQ
//

import SwiftUI
import UniformTypeIdentifiers

struct ScriptsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showImporter = false
    @State private var showEditor = false
    @State private var draft = ""
    @State private var draftName = "custom.js"
    @State private var previewBundled = false

    private var scriptsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var customScripts: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: scriptsDirectory.path))?
            .filter { $0.hasSuffix(".js") }
            .sorted() ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card(title: "内置脚本", systemImage: "curlybraces") {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("jit26.js")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("iOS 26 JIT 页协议 · brk #0xf00d")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            StatusPill(text: "就绪", ok: true)
                        }
                        HStack(spacing: 10) {
                            ActionButton(title: "用脚本开 JIT", systemImage: "play.fill", prominent: true) {
                                model.runScriptOnLastApp()
                            }
                            ActionButton(title: previewBundled ? "收起" : "查看", systemImage: "eye") {
                                previewBundled.toggle()
                            }
                        }
                        if previewBundled {
                            Text(AppModel.bundledScript)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Theme.cardAlt)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Card(title: "自定义脚本", systemImage: "folder") {
                        if customScripts.isEmpty {
                            Text("还没有脚本。可以从文件导入 .js，脚本里可用 log / send_command / prepare_memory_region / get_pid。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            ForEach(customScripts, id: \.self) { name in
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(Theme.accent)
                                    Text(name)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Button {
                                        run(name)
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        delete(name)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        HStack(spacing: 10) {
                            ActionButton(title: "导入脚本", systemImage: "square.and.arrow.down", prominent: true) {
                                showImporter = true
                            }
                            ActionButton(title: "新建脚本", systemImage: "plus") {
                                draftName = "custom-\(Int(Date().timeIntervalSince1970)).js"
                                draft = "// JIT RPOQ 脚本\nlog(\"hello\");\n"
                                showEditor = true
                            }
                        }
                    }

                    Card(title: "脚本接口", systemImage: "terminal") {
                        VStack(alignment: .leading, spacing: 6) {
                            api("log(text)", "输出到日志")
                            api("send_command(cmd)", "发送 debugserver 命令，返回响应")
                            api("prepare_memory_region(addr, size)", "把内存页标记为可执行")
                            api("get_pid()", "当前附加进程的 PID")
                            api("sleep_ms(n)", "阻塞等待")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("脚本")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "js") ?? .data, .data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    importScript(url)
                }
            case .failure(let error):
                model.append("导入脚本失败：\(error.localizedDescription)", error: true)
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                    .padding(12)
                    .navigationTitle(draftName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("取消") { showEditor = false }
                                .foregroundStyle(Theme.textSecondary)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("保存") {
                                try? draft.write(to: scriptsDirectory.appendingPathComponent(draftName), atomically: true, encoding: .utf8)
                                showEditor = false
                            }
                            .foregroundStyle(Theme.accent)
                        }
                    }
            }
        }
    }

    private func api(_ name: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private func run(_ name: String) {
        guard let bundle = model.lastBundleID, let app = model.app(named: bundle) else {
            model.append("先选一个目标应用（在应用页开一次 JIT）", error: true)
            return
        }
        guard let text = try? String(contentsOf: scriptsDirectory.appendingPathComponent(name), encoding: .utf8) else {
            model.append("脚本读取失败", error: true)
            return
        }
        model.enable(app, script: text)
    }

    private func importScript(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            model.append("脚本不是 UTF-8 文本", error: true)
            return
        }
        try? text.write(to: scriptsDirectory.appendingPathComponent(url.lastPathComponent), atomically: true, encoding: .utf8)
        model.append("脚本已导入：\(url.lastPathComponent)")
    }

    private func delete(_ name: String) {
        try? FileManager.default.removeItem(at: scriptsDirectory.appendingPathComponent(name))
    }
}
