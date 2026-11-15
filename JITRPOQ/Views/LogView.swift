//
//  LogView.swift
//  JIT RPOQ
//

import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel

    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.logs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.textSecondary)
                        Text("暂无日志")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("开启 JIT 后这里会显示隧道、附加、脚本的过程")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(model.logs.reversed()) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatter.string(from: entry.time))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(entry.text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(entry.isError ? Theme.red : Theme.textPrimary.opacity(0.85))
                                        .textSelection(.enabled)
    						}
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = model.logs.map(\.text).joined(separator: "\n")
                        } label: {
                            Label("复制全部", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            model.clearLogs()
                        } label: {
                            Label("清空", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }
}
