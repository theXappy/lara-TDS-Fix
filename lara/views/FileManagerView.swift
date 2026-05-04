//
//  FileManagerView.swift
//  lara — TDS fork
//
//  RC-backed file manager — Implementation 1.
//
//  Features:
//    ─ Breadcrumb navigation with hardened symlink-loop prevention
//    ─ Directory listing: VFS → FileManager → RC opendir (3-tier)
//    ─ File operations: read, write, copy, paste, delete, rename, upload
//    ─ New folder creation via RC mkdir
//    ─ Directory bookmarks (persistent via UserDefaults)
//    ─ Process override ("Isolate") propagated to ALL operations
//    ─ Process pool access via ProcessSelectorView
//    ─ Process Inspector guidance (link to add live processes to RC pool)
//    ─ Lara FM accessible via toolbar (presented as sheet to avoid nav conflicts)
//    ─ Verbose debug panel: pool summary, op log, override pill, list source
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileManagerView

struct FileManagerView: View {
    @ObservedObject private var mgr  = laramgr.shared
    @ObservedObject private var rcio = RemoteFileIO.shared

    @State private var path: String = "/"
    @State private var entries: [(name: String, isDir: Bool, size: Int64)] = []
    @State private var listSource: String = ""
    @State private var loading    = false
    @State private var status: String?

    // File operation state
    @State private var selectedFile: String?
    @State private var showPicker   = false
    @State private var pickedData:  Data?
    @State private var pickedName:  String?

    // Preview
    @State private var previewPath:   String?
    @State private var previewResult: (data: Data?, result: RCIOResult)?
    @State private var showPreview    = false

    // Debug panel
    @State private var showDebug = true
    @State private var showLog   = false
    @State private var lastOpResult: RCIOResult?

    // Process selector / override
    @State private var showProcessSelector = false
    @State private var processOverride: String? = nil   // nil = auto-routing

    // Process inspector guidance
    @State private var showProcessInspector = false

    // Lara FM sheet
    @State private var showLaraFM = false

    // Bookmarks
    @State private var showBookmarks      = false
    @State private var showAddBookmark    = false
    @State private var bookmarkLabel      = ""

    // New folder
    @State private var showNewFolder  = false
    @State private var newFolderName  = ""

    // Load generation counter (prevents stale results from overwriting newer loads)
    @State private var loadGeneration: Int = 0

    // Delete
    @State private var deleteTarget:     String?
    @State private var showDeleteConfirm = false

    // Copy / Paste
    @State private var copyBuffer: (path: String, name: String)?

    // Rename
    @State private var renameTarget: String?
    @State private var renameDest:   String = ""
    @State private var showRename    = false

    // Path bar (manual entry)
    @State private var showPathEntry = false
    @State private var manualPath    = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            if showDebug { debugPanel }
            fileList
        }
        .navigationTitle("RC File Manager")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Leading: Lara FM + Bookmarks
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button {
                    showLaraFM = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Lara FM")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                .disabled(!mgr.sbxready && !mgr.vfsready)

                Menu {
                    // Quick bookmarks menu
                    if rcio.bookmarks.isEmpty {
                        Text("No bookmarks yet")
                    } else {
                        ForEach(rcio.bookmarks) { bm in
                            Button {
                                navigate(to: bm.path)
                            } label: {
                                Label(bm.displayName, systemImage: "bookmark.fill")
                            }
                        }
                        Divider()
                    }

                    Button {
                        showBookmarks = true
                    } label: {
                        Label("Manage Bookmarks", systemImage: "list.bullet")
                    }

                    Divider()

                    Button {
                        bookmarkLabel = URL(fileURLWithPath: path).lastPathComponent
                        showAddBookmark = true
                    } label: {
                        Label("Bookmark This Directory", systemImage: "bookmark.fill")
                    }

                    // Common paths
                    Divider()
                    Button { navigate(to: "/") } label: { Label("/", systemImage: "slash.circle") }
                    Button { navigate(to: "/var") } label: { Label("/var", systemImage: "folder") }
                    Button { navigate(to: "/var/mobile") } label: { Label("/var/mobile", systemImage: "folder") }
                    Button { navigate(to: "/var/mobile/Containers") } label: { Label("/var/mobile/Containers", systemImage: "folder") }
                    Button { navigate(to: "/var/root") } label: { Label("/var/root", systemImage: "folder.badge.person.crop") }
                } label: {
                    Image(systemName: rcio.bookmarks.isEmpty ? "bookmark" : "bookmark.fill")
                        .foregroundColor(rcio.bookmarks.isEmpty ? .secondary : .yellow)
                }
            }

            // Trailing: paste buffer, debug toggle, new folder, upload
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let buf = copyBuffer {
                    Button { handlePaste(buf) } label: {
                        Label("Paste \(buf.name)", systemImage: "doc.on.clipboard.fill")
                            .foregroundColor(.mint)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                Menu {
                    Button {
                        showPicker   = true
                        selectedFile = nil
                    } label: {
                        Label("Upload File", systemImage: "arrow.up.doc")
                    }
                    .disabled(!mgr.dsready)

                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(!mgr.dsready)

                    Divider()

                    Button {
                        manualPath = path
                        showPathEntry = true
                    } label: {
                        Label("Go to Path…", systemImage: "arrow.right.circle")
                    }
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    withAnimation { showDebug.toggle() }
                } label: {
                    Image(systemName: showDebug ? "ant.fill" : "ant")
                        .foregroundColor(showDebug ? .orange : .secondary)
                }
            }
        }
        // Alerts
        .alert("Status", isPresented: .constant(status != nil)) {
            Button("OK") { status = nil }
        } message: { Text(status ?? "") }
        .alert("Delete", isPresented: $showDeleteConfirm, presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) { handleDelete(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Permanently delete \(URL(fileURLWithPath: target).lastPathComponent)?")
        }
        .alert("Rename", isPresented: $showRename, presenting: renameTarget) { target in
            TextField("New name", text: $renameDest)
            Button("Rename") {
                let dest = (path == "/" ? "" : path) + "/" + renameDest
                handleMove(from: target, to: dest)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Rename \(URL(fileURLWithPath: target).lastPathComponent)")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { handleNewFolder() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a new folder in \(URL(fileURLWithPath: path).lastPathComponent.isEmpty ? "/" : URL(fileURLWithPath: path).lastPathComponent)")
        }
        .alert("Bookmark", isPresented: $showAddBookmark) {
            TextField("Label (optional)", text: $bookmarkLabel)
            Button("Save") {
                rcio.addBookmark(path: path, label: bookmarkLabel)
                status = "Bookmarked: \(path)"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Bookmark \(path)")
        }
        .alert("Go to Path", isPresented: $showPathEntry) {
            TextField("Path", text: $manualPath)
            Button("Go") { navigate(to: manualPath) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a filesystem path")
        }
        // Sheets
        .sheet(isPresented: $showPicker) {
            RCFilePicker(data: $pickedData, filename: $pickedName)
        }
        .sheet(isPresented: $showPreview) {
            if let path = previewPath, let res = previewResult {
                FilePreviewSheet(path: path, data: res.data, result: res.result)
            }
        }
        .sheet(isPresented: $showLaraFM) {
            SantanderView(startPath: "/")
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showProcessSelector) {
            ProcessSelectorView(
                pathContext:      path,
                selectedOverride: $processOverride
            )
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkManagerSheet(rcio: rcio) { bmPath in
                navigate(to: bmPath)
                showBookmarks = false
            }
        }
        .sheet(isPresented: $showProcessInspector) {
            ProcessInspectorView()
        }
        .onChange(of: pickedData) { data in
            guard let data else { return }
            pickedData = nil
            handlePickedData(data)
        }
        .onAppear { loadEntries() }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Button("/") { navigate(to: "/") }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.blue)

                ForEach(Array(pathComponents.enumerated()), id: \.offset) { i, part in
                    Text(" / ")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button(part) {
                        navigate(to: "/" + pathComponents[0...i].joined(separator: "/"))
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var pathComponents: [String] {
        path.components(separatedBy: "/").filter { !$0.isEmpty }
    }

    // MARK: - Debug panel

    private var debugPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Processes button → opens ProcessSelectorView
                Button {
                    showProcessSelector = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(poolSummaryLabel)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .tint(anyReady ? .green : .secondary)
                .controlSize(.mini)

                // Override pill
                if let ov = processOverride {
                    Button {
                        processOverride = nil
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(ov)
                                .font(.system(size: 11, design: .monospaced))
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.mini)
                } else {
                    Text("→ \(rcio.rcBestProcess(for: path))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Process Inspector shortcut
                Button {
                    showProcessInspector = true
                } label: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                .controlSize(.mini)

                // Op log toggle
                Button {
                    withAnimation { showLog.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet.rectangle")
                        if !rcio.log.isEmpty {
                            Text("\(rcio.log.count)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(showLog ? .orange : .secondary)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if showLog {
                opLogView
            }

            if let r = lastOpResult {
                lastOpBar(r)
            }

            if !listSource.isEmpty {
                HStack {
                    Text("src:\(listSource)  \(entries.count) entries  \(path)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }

            Divider()
        }
        .background(Color(.tertiarySystemBackground))
    }

    private var opLogView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Clear") { rcio.clearLog(); lastOpResult = nil }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if rcio.log.isEmpty {
                        Text("no operations yet")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    ForEach(rcio.log.prefix(30)) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.summary)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(entry.result.ok ? .primary : .red)
                            if !entry.result.diagnostic.isEmpty {
                                Text("  ↳ \(entry.result.diagnostic)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 140)
        }
    }

    @ViewBuilder
    private func lastOpBar(_ r: RCIOResult) -> some View {
        HStack {
            Circle()
                .fill(r.ok ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(r.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(r.ok ? .primary : .red)
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.0fms", r.duration * 1000))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            tierBadge(r.tier)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tierBadge(_ tier: RCIOTier) -> some View {
        let color: Color = {
            switch tier {
            case .direct:     return .green
            case .vfs:        return .blue
            case .remoteCall: return .orange
            case .failed:     return .red
            }
        }()
        Text(tier.rawValue)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)))
    }

    // MARK: - File list

    private var fileList: some View {
        List {
            if loading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Loading...").foregroundColor(.secondary)
                    Spacer()
                }
            } else if entries.isEmpty {
                VStack(spacing: 8) {
                    Text("Empty or inaccessible")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    if !anyReady {
                        Text("No RC processes are active. Open Processes to initialise them, or use the Process Inspector to add live processes to the pool.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("Open Processes") { showProcessSelector = true }
                                .font(.system(size: 12, design: .monospaced))
                                .buttonStyle(.bordered)
                                .tint(.green)
                            Button("Process Inspector") { showProcessInspector = true }
                                .font(.system(size: 12, design: .monospaced))
                                .buttonStyle(.bordered)
                                .tint(.purple)
                        }
                    }
                }
                .padding(.vertical, 8)
            } else {
                // Parent directory button
                if path != "/" {
                    Button {
                        let parent = (path as NSString).deletingLastPathComponent
                        navigate(to: parent.isEmpty ? "/" : parent)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.doc.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 22)
                            Text("..")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                ForEach(entries, id: \.name) { entry in
                    entryRow(entry)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { loadEntries() }
    }

    @ViewBuilder
    private func entryRow(_ entry: (name: String, isDir: Bool, size: Int64)) -> some View {
        let fullPath = (path == "/" ? "" : path) + "/" + entry.name

        HStack(spacing: 10) {
            Image(systemName: entry.isDir ? (entry.size == -2 ? "folder.fill.badge.questionmark" : "folder.fill") : fileIcon(for: entry.name))
                .foregroundColor(entry.isDir ? (entry.size == -2 ? .orange : .yellow) : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if !entry.isDir {
                    HStack(spacing: 6) {
                        Text(entry.size.fileSizeString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        let effective = processOverride ?? rcio.rcBestProcess(for: fullPath)
                        Text(effective)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(processOverride != nil ? .orange : .secondary)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill((processOverride != nil ? Color.orange : Color.secondary).opacity(0.1))
                            )
                    }
                }
            }

            Spacer()

            if !entry.isDir {
                Button { openPreview(path: fullPath, size: entry.size) } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)

                Button {
                    selectedFile = fullPath
                    showPicker   = true
                } label: {
                    Image(systemName: "arrow.up.doc")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if entry.isDir { navigate(to: fullPath) } }
        .swipeActions(edge: .leading) {
            Button {
                UIPasteboard.general.string = fullPath
                status = "Copied: \(fullPath)"
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .tint(.blue)

            Button {
                copyBuffer = (path: fullPath, name: entry.name)
                status = entry.isDir ? "Directories cannot be copied yet" : "Buffered: \(entry.name)"
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .tint(.mint)
            .disabled(entry.isDir)

            Button {
                renameTarget = fullPath
                renameDest   = entry.name
                showRename   = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTarget      = fullPath
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            if !entry.isDir {
                Button {
                    selectedFile = fullPath
                    showPicker   = true
                } label: {
                    Label("Overwrite", systemImage: "arrow.up.doc.fill")
                }
                .tint(.orange)
            }

            if entry.isDir {
                Button {
                    bookmarkLabel = entry.name
                    rcio.addBookmark(path: fullPath, label: entry.name)
                    status = "Bookmarked: \(entry.name)"
                } label: {
                    Label("Bookmark", systemImage: "bookmark.fill")
                }
                .tint(.yellow)
            }
        }
    }

    // MARK: - Navigation and loading

    /// Navigate to a path with hardened symlink-loop prevention.
    ///
    /// IMPORTANT: do NOT use realpath() here.
    ///   realpath("/var") resolves to "/private/var" because /var is a symlink on iOS.
    ///   The VFS layer indexes inodes under the symlinked form (/var/...), so passing
    ///   the canonical /private/var form causes vfslistdir to return nil, FM then
    ///   fails (sandbox), and the listing appears empty or as root.
    ///
    ///   URL.standardized collapses ".." and "//" without following symlinks.
    ///   listDir() in RemoteFileIO internally retries both /var and /private/var.
    private func navigate(to newPath: String) {
        var normalized = URL(fileURLWithPath: newPath).standardized.path

        // Kill doubled /private prefix: /private/private/... → /private/...
        while normalized.hasPrefix("/private/private") {
            normalized = "/private" + String(normalized.dropFirst("/private/private".count))
        }

        // Safety: prevent circular symlink explosion — cap depth at 30 components
        let components = normalized.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count > 30 {
            status = "Path too deep — possible symlink loop"
            return
        }

        // Detect and prevent identical repeated path segments (e.g. /var/var/var/...)
        if components.count >= 4 {
            let last3 = Array(components.suffix(3))
            if last3[0] == last3[1] && last3[1] == last3[2] {
                status = "Symlink loop detected at \(last3[0])"
                return
            }
        }

        path = normalized.isEmpty ? "/" : normalized
        loadEntries()
    }

    private func loadEntries() {
        loadGeneration &+= 1
        let gen         = loadGeneration
        let targetPath  = path
        loading    = true
        entries    = []
        listSource = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let (e, src) = self.rcio.listDir(path: targetPath, override: self.processOverride)
            DispatchQueue.main.async {
                guard self.loadGeneration == gen else { return }
                self.entries    = e
                self.listSource = src
                self.loading    = false
            }
        }
    }

    // MARK: - File operations (all pass processOverride)

    private func handlePickedData(_ data: Data) {
        let target: String
        if let sel = selectedFile {
            target = sel
        } else {
            let name = pickedName ?? "lara_new_\(Int(Date().timeIntervalSince1970)).bin"
            target = (path == "/" ? "" : path) + "/" + name
        }
        selectedFile = nil
        pickedName   = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = rcio.write(path: target, data: data, override: self.processOverride)
            DispatchQueue.main.async {
                self.lastOpResult = result
                self.status       = result.message
                if result.ok { self.loadEntries() }
            }
        }
    }

    private func openPreview(path: String, size: Int64) {
        previewPath   = path
        previewResult = nil
        showPreview   = true

        let maxSize = size > 0 ? Int(size) : 8 * 1024 * 1024

        DispatchQueue.global(qos: .userInitiated).async {
            let (data, result) = rcio.read(path: path, maxSize: maxSize,
                                           override: self.processOverride)
            DispatchQueue.main.async {
                self.previewResult = (data, result)
                self.lastOpResult  = result
            }
        }
    }

    private func handleDelete(_ path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = rcio.delete(path: path, override: self.processOverride)
            DispatchQueue.main.async {
                self.lastOpResult = result
                self.status       = result.message
                if result.ok { self.loadEntries() }
            }
        }
    }

    private func handlePaste(_ buf: (path: String, name: String)) {
        let dest = (path == "/" ? "" : path) + "/" + buf.name
        DispatchQueue.global(qos: .userInitiated).async {
            let (data, readResult) = rcio.read(path: buf.path, override: self.processOverride)
            guard let data else {
                DispatchQueue.main.async { self.status = "Copy failed: \(readResult.message)" }
                return
            }
            let writeResult = rcio.write(path: dest, data: data, override: self.processOverride)
            DispatchQueue.main.async {
                self.lastOpResult = writeResult
                self.status       = writeResult.message
                if writeResult.ok {
                    self.copyBuffer = nil
                    self.loadEntries()
                }
            }
        }
    }

    private func handleMove(from src: String, to dst: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = rcio.move(from: src, to: dst, override: self.processOverride)
            DispatchQueue.main.async {
                self.lastOpResult = result
                self.status       = result.message
                if result.ok { self.loadEntries() }
            }
        }
    }

    private func handleNewFolder() {
        guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let target = (path == "/" ? "" : path) + "/" + newFolderName
        DispatchQueue.global(qos: .userInitiated).async {
            let result = rcio.mkdir(path: target, override: self.processOverride)
            DispatchQueue.main.async {
                self.lastOpResult = result
                self.status       = result.message
                if result.ok { self.loadEntries() }
            }
        }
    }

    // MARK: - Pool helpers

    private var anyReady: Bool {
        rcio.pool.values.contains { $0.state.isReady }
    }

    private var poolSummaryLabel: String {
        let ready = rcio.pool.values.filter { $0.state.isReady }.count
        let total = RemoteFileIO.recommendedProcesses.count
        return "Procs \(ready)/\(total)"
    }

    // MARK: - Icon helper

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "plist":                          return "list.bullet.rectangle"
        case "png", "jpg", "jpeg", "webp", "heic": return "photo"
        case "mp4", "mov", "m4v":              return "film"
        case "mp3", "m4a", "aac":              return "music.note"
        case "pdf":                            return "doc.richtext"
        case "dylib", "so":                    return "gear"
        case "db", "sqlite":                   return "cylinder"
        case "bin", "img":                     return "cpu"
        case "swift", "h", "m", "c", "cpp":   return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml":            return "curlybraces"
        case "log", "txt":                     return "doc.text"
        case "ipa", "deb":                     return "shippingbox"
        default:                               return "doc"
        }
    }
}

// MARK: - Bookmark Manager Sheet

struct BookmarkManagerSheet: View {
    @ObservedObject var rcio: RemoteFileIO
    var onNavigate: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if rcio.bookmarks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text("No bookmarks")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Swipe left on a directory to bookmark it, or use the bookmark menu in the toolbar.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(rcio.bookmarks) { bm in
                        Button {
                            onNavigate(bm.path)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundColor(.yellow)
                                    Text(bm.displayName)
                                        .font(.system(.body, design: .monospaced))
                                }
                                Text(bm.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Text(bm.createdAt, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        rcio.removeBookmark(at: offsets)
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - File preview sheet

struct FilePreviewSheet: View {
    let path:   String
    let data:   Data?
    let result: RCIOResult

    @Environment(\.dismiss) private var dismiss
    @State private var viewMode: PreviewMode = .auto

    enum PreviewMode: String, CaseIterable { case auto, text, hex, plist }

    private var filename: String { URL(fileURLWithPath: path).lastPathComponent }

    init(path: String, data: Data?, result: RCIOResult) {
        self.path = path
        self.data = data
        self.result = result
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                resultBanner
                Picker("Mode", selection: $viewMode) {
                    ForEach(PreviewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                ScrollView {
                    if let data {
                        contentView(data: data).padding()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40)).foregroundColor(.red)
                            Text("Failed to read file").font(.headline)
                            Text(result.diagnostic)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }.padding(40)
                    }
                }
            }
            .navigationTitle(filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let data {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: data, preview: SharePreview(filename))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(result.ok ? Color.green : Color.red).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.message)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                if !result.diagnostic.isEmpty && result.diagnostic != result.message {
                    Text(result.diagnostic)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let c: Color = {
                    switch result.tier {
                    case .direct:     return .green
                    case .vfs:        return .blue
                    case .remoteCall: return .orange
                    case .failed:     return .red
                    }
                }()
                Text(result.tier.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(c)
                if let proc = result.process {
                    Text(proc)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(String(format: "%.0fms", result.duration * 1000))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func contentView(data: Data) -> some View {
        switch effectiveMode(for: data) {
        case .plist:
            if let pl = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let xd = try? PropertyListSerialization.data(fromPropertyList: pl, format: .xml, options: 0),
               let xs = String(data: xd, encoding: .utf8) {
                Text(xs)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else { fallbackText(data: data) }
        case .text:
            fallbackText(data: data)
        case .hex:
            Text(hexDump(data: data))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .auto:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fallbackText(data: Data) -> some View {
        if let str = String(data: data, encoding: .utf8) {
            Text(str)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(hexDump(data: data))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func effectiveMode(for data: Data) -> PreviewMode {
        if viewMode != .auto { return viewMode }
        if (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil { return .plist }
        if String(data: data.prefix(512), encoding: .utf8) != nil { return .text }
        return .hex
    }

    private func hexDump(data: Data) -> String {
        let cap   = min(data.count, 4096)
        let bytes = Array(data.prefix(cap))
        var lines: [String] = []
        stride(from: 0, to: bytes.count, by: 16).forEach { i in
            let chunk = bytes[i..<min(i + 16, bytes.count)]
            let hex   = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = chunk.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append(String(format: "%08x  %-47s  |%@|", i, hex, ascii))
        }
        if data.count > cap { lines.append("... (\(data.count) bytes total)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - File picker wrapper

private struct RCFilePicker: UIViewControllerRepresentable {
    @Binding var data: Data?
    @Binding var filename: String?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: RCFilePicker
        init(_ p: RCFilePicker) { parent = p }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            parent.data     = try? Data(contentsOf: url)
            parent.filename = url.lastPathComponent
        }
    }
}
