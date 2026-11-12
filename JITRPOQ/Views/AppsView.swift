//
//  AppsView.swift
//  JIT RPOQ
//

import SwiftUI
import UIKit

struct AppsView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var filter: Filter = .jit
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    enum Filter: String, CaseIterable {
        case jit = "可开 JIT"
        case all = "全部"
        case favourite = "收藏"
    }

    private var filtered: [InstalledApp] {
        model.apps.filter { app in
            if filter == .jit && !app.isJITCapable && !model.favourites.contains(app.bundleID) { return false }
            if filter == .favourite && !model.favourites.contains(app.bundleID) { return false }
            if query.isEmpty { return true }
            return app.name.localizedCaseInsensitiveContains(query) || app.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if model.isLoadingApps {
                    ProgressView("正在读取设备上的应用…")
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 40)
                    Spacer()
                } else if model.apps.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { app in
                                row(app)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "搜索应用或 BundleID")
            .navigationTitle("应用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "取消" : "选择") {
                        isSelecting.toggle()
                        selection.removeAll()
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(model.apps.isEmpty || model.batchRunning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refreshApps()
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Theme.accent)
                    }
                    .disabled(model.isLoadingApps || !model.pairingExists)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting || model.batchRunning {
                    selectionBar
                }
            }
            .refreshable { model.refreshApps() }
            .onAppear {
                model.loadIconsIfNeeded()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text(model.pairingExists ? "还没读取应用列表" : "请先导入配对文件")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(model.vpnConnected ? "点右上角刷新，读取设备上的应用" : "打开 LocalDevVPN 连接后，再点刷新")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            ActionButton(title: "刷新应用列表", systemImage: "arrow.clockwise", prominent: true, disabled: !model.pairingExists) {
                model.refreshApps()
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 50)
    }

    private var selectionBar: some View {
        VStack(spacing: 8) {
            if model.batchRunning {
                ProgressView(value: Double(model.batchDone), total: Double(max(model.batchTotal, 1)))
                    .tint(Theme.accent)
                Text("正在开启 \(model.batchDone)/\(model.batchTotal)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                Button("全选可开 JIT") {
                    selection = Set(filtered.filter { $0.isJITCapable }.map(\.bundleID))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .disabled(model.batchRunning)

                Spacer()

                ActionButton(
                    title: "一键开 JIT (\(selection.count))",
                    systemImage: "bolt.fill",
                    prominent: true,
                    disabled: selection.isEmpty || model.batchRunning
                ) {
                    let targets = filtered.filter { selection.contains($0.bundleID) }
                    model.enableBatch(targets)
                    isSelecting = false
                    selection.removeAll()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
    }

    private func row(_ app: InstalledApp) -> some View {
        Button {
            if isSelecting {
                guard app.isJITCapable else { return }
                if selection.contains(app.bundleID) {
                    selection.remove(app.bundleID)
                } else {
                    selection.insert(app.bundleID)
                }
            } else {
                model.enable(app)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selection.contains(app.bundleID) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(app.isJITCapable
                                         ? (selection.contains(app.bundleID) ? Theme.accent : Theme.textSecondary)
                                         : Theme.textSecondary.opacity(0.4))
                }
                PackageIcon(image: model.icon(for: app.bundleID), name: app.name)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if model.favourites.contains(app.bundleID) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accent2)
                        }
                    }
                    Text(app.bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if app.isJITCapable {
                            Text("get-task-allow")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.green.opacity(0.12))
                                .clipShape(Capsule())
                        } else if app.isSystem {
                            Text("系统应用")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("无 JIT 权限")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.red.opacity(0.8))
                        }
                        if !app.version.isEmpty {
                            Text("v\(app.version)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
                if model.busyBundle == app.bundleID {
                    ProgressView()
                        .tint(Theme.accent)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(app.isJITCapable ? Theme.accent : Theme.textSecondary.opacity(0.5))
                }
            }
            .padding(12)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.enable(app)
            } label: {
                Label("开启 JIT", systemImage: "bolt.fill")
            }
            Button {
                model.launchOnly(app)
            } label: {
                Label("普通启动", systemImage: "play.fill")
            }
            Button {
                model.toggleFavourite(app)
            } label: {
                Label(model.favourites.contains(app.bundleID) ? "取消收藏" : "收藏", systemImage: "star")
            }
            if let url = URL(string: "jitrpoq://enable?bundle=\(app.bundleID)") {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("复制跳转链接", systemImage: "link")
                }
            }
        }
    }
}
