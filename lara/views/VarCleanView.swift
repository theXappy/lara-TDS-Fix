//
//  VarCleanView.swift
//  lara
//

import SwiftUI

private struct VarCleanMatch: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    var isSelected: Bool

    var id: String { path }
}

private struct VarCleanGroup: Identifiable, Hashable {
    let path: String
    var items: [VarCleanMatch]

    var id: String { path }
}

struct VarCleanView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var groups: [VarCleanGroup] = []
    @State private var isRefreshing = false
    @State private var isDeleting = false
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false

    private var cleanupAvailable: Bool { mgr.sbxready }

    private var selectedCount: Int {
        groups.reduce(0) { $0 + $1.items.filter(\.isSelected).count }
    }

    var body: some View {
        List {
            Section("Status") {
                Text(cleanupAvailable
                     ? "Cleanup enabled via sandbox escape."
                     : "Detection only. Escape the sandbox to delete matched paths.")
                    .foregroundColor(.secondary)

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }

            if groups.isEmpty && !isRefreshing {
                Section("Matches") {
                    Text("No blacklisted residue from VarCleanRules.json was found.")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(groups.indices, id: \.self) { groupIndex in
                    Section(groups[groupIndex].path) {
                        ForEach(groups[groupIndex].items.indices, id: \.self) { itemIndex in
                            let item = groups[groupIndex].items[itemIndex]
                            Button {
                                guard cleanupAvailable else { return }
                                groups[groupIndex].items[itemIndex].isSelected.toggle()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(item.isSymlink ? "🔗" : (item.isDirectory ? "🗂️" : "📄"))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .foregroundColor(.primary)
                                        Text(item.path)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if cleanupAvailable {
                                        Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(item.isSelected ? .red : .secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!cleanupAvailable)
                        }
                    }
                }
            }
        }
        .navigationTitle("VarClean")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing || isDeleting)

                Button(selectedCount == 0 ? "Select All" : "Clear") {
                    toggleSelection()
                }
                .disabled(!cleanupAvailable || groups.isEmpty || isDeleting)

                Button("Clean") {
                    showDeleteConfirmation = true
                }
                .disabled(!cleanupAvailable || selectedCount == 0 || isDeleting)
            }
        }
        .task {
            await refresh()
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteSelected() }
            }
        } message: {
            Text("Delete \(selectedCount) matched path\(selectedCount == 1 ? "" : "s")?")
        }
    }

    private func toggleSelection() {
        let shouldSelect = selectedCount == 0
        for groupIndex in groups.indices {
            for itemIndex in groups[groupIndex].items.indices {
                groups[groupIndex].items[itemIndex].isSelected = shouldSelect
            }
        }
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let newGroups = await Task.detached(priority: .userInitiated) {
            loadVarCleanGroups()
        }.value

        groups = newGroups
        if groups.isEmpty {
            statusMessage = nil
        } else {
            let matchCount = groups.reduce(0) { $0 + $1.items.count }
            statusMessage = "Found \(matchCount) matched path\(matchCount == 1 ? "" : "s")."
        }
    }

    @MainActor
    private func deleteSelected() async {
        guard cleanupAvailable else { return }
        isDeleting = true
        defer { isDeleting = false }

        let selectedPaths = groups
            .flatMap(\.items)
            .filter(\.isSelected)
            .map(\.path)
            .sorted { $0.count > $1.count }

        var deletedCount = 0
        var failures: [String] = []
        let fileManager = FileManager.default

        for path in selectedPaths {
            do {
                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(atPath: path)
                }
                deletedCount += 1
            } catch {
                failures.append("\(path): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            statusMessage = "Deleted \(deletedCount) path\(deletedCount == 1 ? "" : "s")."
        } else {
            statusMessage = "Deleted \(deletedCount) path\(deletedCount == 1 ? "" : "s"), failed \(failures.count)."
        }

        await refresh()
    }
}

private func loadVarCleanGroups() -> [VarCleanGroup] {
    var error: NSError?
    guard let rules = VarCleanBridge.loadRulesNamed("VarCleanRules", in: .main, error: &error) as? [String: Any] else {
        return []
    }

    var grouped: [String: [VarCleanMatch]] = [:]
    var seenPaths = Set<String>()
    var directoryEntriesCache: [String: [String]] = [:]
    let sortedRulePaths = rules.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    for basePath in sortedRulePaths {
        guard let rule = rules[basePath] as? [String: Any],
              let blacklist = rule["blacklist"] as? [Any] else {
            continue
        }

        for probePath in probePaths(
            for: basePath,
            blacklist: blacklist,
            seenPaths: &seenPaths,
            directoryEntriesCache: &directoryEntriesCache
        ) {
            var isDirectory = ObjCBool(false)
            var isSymlink = ObjCBool(false)
            guard VarCleanBridge.probePathExists(probePath, isDirectory: &isDirectory, isSymlink: &isSymlink) else {
                continue
            }

            let groupPath = (probePath as NSString).deletingLastPathComponent.isEmpty
                ? "/"
                : (probePath as NSString).deletingLastPathComponent

            let match = VarCleanMatch(
                path: probePath,
                name: (probePath as NSString).lastPathComponent,
                isDirectory: isDirectory.boolValue,
                isSymlink: isSymlink.boolValue,
                isSelected: false
            )
            grouped[groupPath, default: []].append(match)
        }
    }

    let sortedGroups = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return sortedGroups.map { groupPath in
        let items = (grouped[groupPath] ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return VarCleanGroup(path: groupPath, items: items)
    }
}

private func probePaths(
    for basePath: String,
    blacklist: [Any],
    seenPaths: inout Set<String>,
    directoryEntriesCache: inout [String: [String]]
) -> [String] {
    var probePaths: [String] = []

    for entry in blacklist {
        if let name = entry as? String, !name.isEmpty {
            let probePath = (basePath as NSString).appendingPathComponent(name)
            if seenPaths.insert(probePath).inserted {
                probePaths.append(probePath)
            }
            continue
        }

        guard let condition = entry as? [String: Any],
              let match = condition["match"] as? String,
              match == "regexp",
              let pattern = condition["name"] as? String,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            continue
        }

        let entries = directoryEntries(atPath: basePath, cache: &directoryEntriesCache)
        for name in entries where regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil {
            let probePath = (basePath as NSString).appendingPathComponent(name)
            if seenPaths.insert(probePath).inserted {
                probePaths.append(probePath)
            }
        }
    }

    return probePaths
}

private func directoryEntries(atPath path: String, cache: inout [String: [String]]) -> [String] {
    if let cached = cache[path] {
        return cached
    }

    let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    cache[path] = entries
    return entries
}
