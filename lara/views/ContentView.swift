//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//  Fork: added File Manager, My Tweaks, and Logs tabs.
//  The Home tab is intentionally verbatim from upstream — do not edit it.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @ObservedObject private var mgr = laramgr.shared
    @State private var hasoffsets = true
    @State private var showsettings = false
    @State private var selectedmethod: method = .hybrid

    var body: some View {
        TabView {

            // MARK: - Tab 1: File Manager (dual-view)
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            SantanderView(startPath: "/")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("File Manager")
                                    Text("Standard lara file browser")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(!mgr.sbxready && !mgr.vfsready)

                        NavigationLink {
                            FileManagerView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.gear")
                                    .foregroundColor(.orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("RC File Manager")
                                    Text("RemoteCall-backed, full filesystem reach")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(!mgr.dsready)
                    } header: {
                        Text("Choose a file browser")
                    } footer: {
                        Group {
                            if !mgr.sbxready && !mgr.vfsready {
                                Text("File Manager requires Sandbox Escape or VFS.")
                            }
                            if !mgr.dsready {
                                Text("RC File Manager requires the exploit to be run first.")
                            }
                        }
                    }
                }
                .navigationTitle("Files")
            }
            .tabItem { Label("File Manager", systemImage: "folder") }

            // MARK: - Tab 2: Home (verbatim from upstream — do not modify)
            NavigationStack {
                List {
                    if !hasoffsets {
                        Section("Setup") {
                            Text("Kernelcache offsets are missing. Download them in Settings.")
                                .foregroundColor(.secondary)
                            Button("Open Settings") {
                                showsettings = true
                            }
                        }
                    } else {
                        Section {
                            Button {
                                offsets_init()
                                mgr.run()
                            } label: {
                                if mgr.dsrunning {
                                    HStack {
                                        ProgressView(value: mgr.dsprogress)
                                            .progressViewStyle(.circular)
                                            .frame(width: 18, height: 18)
                                        Text("Running...")
                                        Spacer()
                                        Text("\(Int(mgr.dsprogress * 100))%")
                                    }
                                } else {
                                    if mgr.dsready {
                                        HStack {
                                            Text("Ran Exploit")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    } else if mgr.dsattempted && mgr.dsfailed {
                                        HStack {
                                            Text("Exploit Failed")
                                            Spacer()
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Run Exploit")
                                    }
                                }
                            }
                            .disabled(mgr.dsrunning)
                            .disabled(mgr.dsready)
                            .disabled(isdebugged())

                            if mgr.dsready {
                                HStack {
                                    Text("kernel_base:")
                                    Spacer()
                                    Text(String(format: "0x%llx", mgr.kernbase))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("kernel_slide:")
                                    Spacer()
                                    Text(String(format: "0x%llx", mgr.kernslide))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }

                            if isdebugged() {
                                Button {
                                    exit(0)
                                } label: {
                                    Text("Detach")
                                }
                                .foregroundColor(.red)
                            }
                        } header: {
                            Text("Kernel Read Write")
                        } footer: {
                            if g_isunsupported {
                                Text("Your device/installation method may not be supported.")
                            }

                            if isdebugged() {
                                Text("Not available while debugger is attached.")
                            }
                        }

                        Section {
                            if selectedmethod == .vfs {
                                Button {
                                    mgr.vfsinit()
                                } label: {
                                    if mgr.vfsrunning {
                                        HStack {
                                            ProgressView(value: mgr.vfsprogress)
                                                .progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Initialising VFS...")
                                            Spacer()
                                            Text("\(Int(mgr.vfsprogress * 100))%")
                                        }
                                    } else if !mgr.vfsready {
                                        if mgr.vfsattempted && mgr.vfsfailed {
                                            HStack {
                                                Text("VFS Init Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Initialise VFS")
                                        }
                                    } else {
                                        HStack {
                                            Text("Initialised VFS")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)

                                if mgr.vfsready {
                                    NavigationLink("Tweaks") {
                                        List {
                                            NavigationLink("Font Overwrite") {
                                                FontPicker(mgr: mgr)
                                            }

                                            NavigationLink("Card Overwrite") {
                                                CardView()
                                            }

                                            NavigationLink("Custom Overwrite") {
                                                CustomView(mgr: mgr)
                                            }

                                            NavigationLink("DirtyZero (Broken)") {
                                                ZeroView(mgr: mgr)
                                            }

                                            if !showfmintabs {
                                                NavigationLink("File Manager") {
                                                    SantanderView(startPath: "/")
                                                }
                                                NavigationLink("RC File Manager") {
                                                    FileManagerView()
                                                }
                                            }
                                        }
                                        .navigationTitle(Text("Tweaks"))
                                    }
                                }
                            } else if selectedmethod == .sbx {
                                Button {
                                    mgr.sbxescape()
                                } label: {
                                    if mgr.sbxrunning {
                                        HStack {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Escaping Sandbox...")
                                        }
                                    } else if !mgr.sbxready {
                                        if mgr.sbxattempted && mgr.sbxfailed {
                                            HStack {
                                                Text("Sandbox Escape Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Escape Sandbox")
                                        }
                                    } else {
                                        HStack {
                                            Text("Sandbox Escaped")
                                            Spacer()
                                            Image(systemName: "checkmark.circle")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)

                                if mgr.sbxready {
                                    NavigationLink("Tweaks") {
                                        List {
                                            if !showfmintabs {
                                                NavigationLink("File Manager") {
                                                    SantanderView(startPath: "/")
                                                }
                                            }

                                            NavigationLink("Card Overwrite") {
                                                CardView()
                                            }

                                            NavigationLink("3 App Bypass") {
                                                AppsView(mgr: mgr)
                                            }

                                            NavigationLink("VarClean") {
                                                VarCleanView()
                                            }

                                            NavigationLink("Unblacklist (Broken?)") {
                                                WhitelistView()
                                            }

                                            if 1 == 2 {
                                                NavigationLink("MobileGestalt") {
                                                    EditorView()
                                                }

                                                NavigationLink("Passcode Theme") {
                                                    PasscodeView(mgr: mgr)
                                                }
                                            }
                                        }
                                        .navigationTitle(Text("Tweaks"))
                                    }
                                }
                            } else {
                                if !mgr.sbxattempted {
                                    Button {
                                        mgr.sbxescape()
                                    } label: {
                                        if mgr.sbxrunning {
                                            HStack {
                                                ProgressView()
                                                    .progressViewStyle(.circular)
                                                    .frame(width: 18, height: 18)
                                                Text("Escaping Sandbox...")
                                            }
                                        } else if !mgr.sbxready {
                                            if mgr.sbxattempted && mgr.sbxfailed {
                                                HStack {
                                                    Text("Sandbox Escape Failed")
                                                    Spacer()
                                                    Image(systemName: "xmark.circle")
                                                        .foregroundColor(.red)
                                                }
                                            } else {
                                                Text("Escape Sandbox")
                                            }
                                        } else {
                                            HStack {
                                                Text("Sandbox Escaped")
                                                Spacer()
                                                Image(systemName: "checkmark.circle")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                    }
                                    .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)
                                } else {
                                    Button {
                                        mgr.vfsinit()
                                    } label: {
                                        if mgr.vfsrunning {
                                            HStack {
                                                ProgressView(value: mgr.vfsprogress)
                                                    .progressViewStyle(.circular)
                                                    .frame(width: 18, height: 18)
                                                Text("Initialising VFS...")
                                                Spacer()
                                                Text("\(Int(mgr.vfsprogress * 100))%")
                                            }
                                        } else if !mgr.vfsready {
                                            if mgr.vfsattempted && mgr.vfsfailed {
                                                HStack {
                                                    Text("VFS Init Failed")
                                                    Spacer()
                                                    Image(systemName: "xmark.circle")
                                                        .foregroundColor(.red)
                                                }
                                            } else {
                                                Text("Initialise VFS")
                                            }
                                        } else {
                                            HStack {
                                                Text("Initialised Hybrid")
                                                Spacer()
                                                Image(systemName: "checkmark.circle")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                    }
                                    .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)
                                }

                                if mgr.vfsready && mgr.sbxready {
                                    NavigationLink("Tweaks") {
                                        List {
                                            if !showfmintabs {
                                                NavigationLink("File Manager") {
                                                    SantanderView(startPath: "/")
                                                }
                                            }

                                            NavigationLink("Font Overwrite") {
                                                FontPicker(mgr: mgr)
                                            }

                                            NavigationLink("Card Overwrite") {
                                                CardView()
                                            }

                                            NavigationLink("Custom Overwrite") {
                                                CustomView(mgr: mgr)
                                            }

                                            NavigationLink("MobileGestalt") {
                                                EditorView()
                                            }

                                            NavigationLink("3 App Bypass") {
                                                AppsView(mgr: mgr)
                                            }

                                            NavigationLink("VarClean") {
                                                VarCleanView()
                                            }

                                            NavigationLink("Whitelist") {
                                                WhitelistView()
                                            }

                                            NavigationLink("DirtyZero") {
                                                ZeroView(mgr: mgr)
                                            }

                                            if 1 == 2 {
                                                NavigationLink("Control Center") {
                                                    CCView()
                                                }

                                                NavigationLink("DarkBoard") {
                                                    DarkBoardView()
                                                }

                                                NavigationLink("Passcode Theme") {
                                                    PasscodeView(mgr: mgr)
                                                }

                                                NavigationLink("3 App Bypass") {
                                                    AppsView(mgr: mgr)
                                                }
                                            }
                                        }
                                        .navigationTitle(Text("Tweaks"))
                                    }
                                }
                            }
                        } header: {
                            Text(selectedmethod == .vfs ? "Virtual File System" : (selectedmethod == .sbx ? "Sandbox Escape" : "Hybrid (SBX + VFS)"))
                        } footer: {
                            if selectedmethod == .sbx {
                                Text("Font Overwrite is only available in VFS or Hybrid mode. (Settings -> Method -> VFS/Hybrid)")
                            }
                        }

                        #if !DISABLE_REMOTECALL
                        Section {
                            Button {
                                mgr.logmsg("T")
                                mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                                    if success {
                                        mgr.logmsg("rc init succeeded!")
                                        let pid = mgr.rccall(name: "getpid")
                                        mgr.logmsg("remote getpid() returned: \(pid)")
                                    } else {
                                        mgr.logmsg("rc init failed")
                                    }
                                }
                            } label: {
                                if mgr.rcrunning {
                                    Text("Initialising RemoteCall...")
                                } else if !mgr.rcready {
                                    Text("Initialise RemoteCall")
                                } else {
                                    HStack {
                                        Text("Initialised RemoteCall")
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .disabled(!mgr.dsready || mgr.rcready)
                            .disabled(isdebugged())

                            if mgr.rcready {
                                NavigationLink("Tweaks") {
                                    RemoteView(mgr: mgr)
                                }

                                Button("Destroy RemoteCall") {
                                    mgr.rcdestroy()
                                }
                            }

                            if isdebugged() {
                                Button {
                                    exit(0)
                                } label: {
                                    Text("Detach")
                                }
                                .foregroundColor(.red)
                            }
                        } header: {
                            Text("RemoteCall")
                        } footer: {
                            if isdebugged() {
                                Text("Not available when a debugger is attached.")
                            }
                            Text("RemoteCall is still in development and may not work properly 100% of the time.")
                        }
                        .disabled(mgr.rcrunning)
                        #endif

                        Section {
                            if mgr.dsready {
                                NavigationLink("Tools") {
                                    ToolsView()
                                }
                            }

                            Button("Respring") {
                                mgr.respring()
                            }

                            Button("Panic!") {
                                mgr.panic()
                            }
                            .disabled(!mgr.dsready)
                        } header: {
                            Text("Other")
                        }
                    }
                }
                .navigationTitle("lara")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showsettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            // MARK: - Tab 3: My Fork's Tweaks
            NavigationStack {
                ForkTweaksView(mgr: mgr, selectedmethod: selectedmethod)
            }
            .tabItem { Label("My Tweaks", systemImage: "wrench.and.screwdriver") }

            // MARK: - Tab 4: Logs
            NavigationStack {
                ForkLogsView(mgr: mgr)
            }
            .tabItem { Label("Logs", systemImage: "scroll") }

        } // end TabView
        .sheet(isPresented: $showsettings) {
            SettingsView(mgr: mgr, hasoffsets: $hasoffsets)
        }
        .onAppear {
            refreshselectedmethod()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshselectedmethod()
        }
    }

    private func refreshselectedmethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}

// MARK: - My Fork's Tweaks tab

/// A standalone tweaks list for this fork.
/// Contains all method-appropriate upstream tweaks PLUS fork-specific features
/// (RC File Manager, Jetsam Memory Manager).
struct ForkTweaksView: View {
    @ObservedObject var mgr: laramgr
    let selectedmethod: method

    var body: some View {
        List {
            // Fork-specific features — always visible
            Section("Fork Features") {
                NavigationLink {
                    FileManagerView()
                } label: {
                    Label("RC File Manager", systemImage: "folder.badge.gear")
                }
                .disabled(!mgr.dsready)

                NavigationLink {
                    JetsamView()
                } label: {
                    Label("Jetsam Memory Manager", systemImage: "memorychip")
                }
            }

            // RC tweaks — shown when RemoteCall is ready
            #if !DISABLE_REMOTECALL
            if mgr.rcready {
                Section("RemoteCall Tweaks") {
                    NavigationLink("SpringBoard Tweaks") {
                        RemoteView(mgr: mgr)
                    }
                }
            }
            #endif

            // Method-appropriate tweaks
            if selectedmethod == .vfs, mgr.vfsready {
                Section("VFS Tweaks") {
                    NavigationLink("Font Overwrite") { FontPicker(mgr: mgr) }
                    NavigationLink("Card Overwrite") { CardView() }
                    NavigationLink("Custom Overwrite") { CustomView(mgr: mgr) }
                    NavigationLink("DirtyZero (Broken)") { ZeroView(mgr: mgr) }
                }
            } else if selectedmethod == .sbx, mgr.sbxready {
                Section("Sandbox Tweaks") {
                    NavigationLink("Card Overwrite") { CardView() }
                    NavigationLink("3 App Bypass") { AppsView(mgr: mgr) }
                    NavigationLink("VarClean") { VarCleanView() }
                    NavigationLink("Unblacklist (Broken?)") { WhitelistView() }
                }
            } else if selectedmethod == .hybrid, mgr.vfsready, mgr.sbxready {
                Section("Tweaks") {
                    NavigationLink("Font Overwrite") { FontPicker(mgr: mgr) }
                    NavigationLink("Card Overwrite") { CardView() }
                    NavigationLink("Custom Overwrite") { CustomView(mgr: mgr) }
                    NavigationLink("MobileGestalt") { EditorView() }
                    NavigationLink("3 App Bypass") { AppsView(mgr: mgr) }
                    NavigationLink("VarClean") { VarCleanView() }
                    NavigationLink("Whitelist") { WhitelistView() }
                    NavigationLink("DirtyZero") { ZeroView(mgr: mgr) }
                }
            } else if !mgr.vfsready && !mgr.sbxready {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.secondary)
                        Text("Initialise the exploit on the Home tab first.")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("My Tweaks")
    }
}

// MARK: - Logs tab

struct ForkLogsView: View {
    @ObservedObject var mgr: laramgr
    @State private var autoscroll = true
    @State private var showClearConfirm = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(mgr.log.isEmpty ? "(no log output yet)" : mgr.log)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(mgr.log.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("bottom")
                    .onChange(of: mgr.log) { _ in
                        if autoscroll {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { autoscroll.toggle() }
                } label: {
                    Image(systemName: autoscroll ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle")
                        .foregroundColor(autoscroll ? .blue : .secondary)
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Clear log?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { mgr.log = "" }
            Button("Cancel", role: .cancel) {}
        }
        .background(Color(.systemBackground))
    }
}
