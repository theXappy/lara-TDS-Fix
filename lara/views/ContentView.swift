//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//  Restructured: Home | Files | Tweaks | Logs | Jetsam
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Method enum (unchanged)

struct ContentView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var hasoffsets = true
    @State private var showsettings = false
    @State private var selectedmethod: method = .hybrid

    let os = ProcessInfo().operatingSystemVersion

    var body: some View {
        TabView {

            // MARK: Tab 1 — Home (exploit init)
            NavigationStack {
                homeContent
            }
            .tabItem { Label("Home", systemImage: "house") }

            // MARK: Tab 2 — Files (Santander + RC File Manager)
            NavigationStack {
                filesContent
            }
            .tabItem { Label("Files", systemImage: "folder") }

            // MARK: Tab 3 — Tweaks
            NavigationStack {
                tweaksContent
            }
            .tabItem { Label("Tweaks", systemImage: "wrench.and.screwdriver") }

            // MARK: Tab 4 — Logs
            NavigationStack {
                LogsView(mgr: mgr)
            }
            .tabItem { Label("Logs", systemImage: "scroll") }

            // MARK: Tab 5 — Jetsam
            NavigationStack {
                JetsamView()
            }
            .tabItem { Label("Jetsam", systemImage: "memorychip") }

        }
        .sheet(isPresented: $showsettings) {
            SettingsView(mgr: mgr, hasoffsets: $hasoffsets)
        }
        .onAppear { refreshselectedmethod() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshselectedmethod()
        }
    }

    // MARK: - Home content (exploit init — no tweaks mixed in)

    private var homeContent: some View {
        List {
            if !hasoffsets {
                Section("Setup") {
                    Text("Kernelcache offsets are missing. Download them in Settings.")
                        .foregroundColor(.secondary)
                    Button("Open Settings") { showsettings = true }
                }
            } else {
                // KRW section
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
                        } else if mgr.dsready {
                            HStack {
                                Text("Ran Exploit")
                                Spacer()
                                Image(systemName: "checkmark.circle").foregroundColor(.green)
                            }
                        } else if mgr.dsattempted && mgr.dsfailed {
                            HStack {
                                Text("Exploit Failed")
                                Spacer()
                                Image(systemName: "xmark.circle").foregroundColor(.red)
                            }
                        } else {
                            Text("Run Exploit")
                        }
                    }
                    .disabled(mgr.dsrunning || mgr.dsready || isdebugged())

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
                        Button("Detach") { exit(0) }.foregroundColor(.red)
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

                            if mgr.vfsready {
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                FontPicker(mgr: mgr)
                                            } label: {
                                                Label("Font Overwrite", systemImage: "textformat.alt")
                                            }

                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }

                                            NavigationLink {
                                                ZeroView(mgr: mgr)
                                            } label: {
                                                Label("DirtyZero", systemImage: "doc")
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }

                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("Remotecall RW Manager", systemImage: "folder")
                                                }
                                                NavigationLink("RC File Manager") {
                                                    FileManagerView()
                                                }
                                            }
                                            
                                            NavigationLink {
                                                CustomView(mgr: mgr)
                                            } label: {
                                                Label("Custom Overwrite", systemImage: "pencil")
                                            }
                                        } header: {
                                            Text("Other")
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
                                }
                            }
                        } else if selectedmethod == .sbx {
                            Button {
                                mgr.sbxescape()
                                // mgr.sbxelevate()
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
                                        Section {
                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }

                                        Section {
                                            NavigationLink {
                                                AppsView(mgr: mgr)
                                            } label: {
                                                Label("3 App Bypass", systemImage: "lock.open.fill")
                                            }

                                            NavigationLink {
                                                WhitelistView()
                                            } label: {
                                                Label("Unblacklist", systemImage: "checkmark.seal")
                                            }
                                        } header: {
                                            Text("App Management")
                                        }

                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }

                                            NavigationLink {
                                                VarCleanView()
                                            } label: {
                                                Label("VarClean", systemImage: "sparkles")
                                            }
                                        } header: {
                                            Text("Other")
                                        }

                                        if 1 == 2 {
                                            NavigationLink {
                                                EditorView()
                                            } label: {
                                                Label("MobileGestalt", systemImage: "gear")
                                            }
                                            NavigationLink {
                                                PasscodeView(mgr: mgr)
                                            } label: {
                                                Label("Passcode Theme", systemImage: "1.circle")
                                            }
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
                                }
                            }
                        } else {
                            HStack {
                                Text("Initialised RemoteCall")
                                Spacer()
                                Image(systemName: "checkmark.circle").foregroundColor(.green)
                            }
                        }
                    }
                    .disabled(!mgr.dsready || mgr.rcready || isdebugged())

                            if mgr.vfsready && mgr.sbxready {
                                NavigationLink("Tweaks") {
                                    List {
                                        Section {
                                            NavigationLink {
                                                FontPicker(mgr: mgr)
                                            } label: {
                                                Label("Font Overwrite", systemImage: "textformat.alt")
                                            }

                                            NavigationLink {
                                                CardView()
                                            } label: {
                                                Label("Card Overwrite", systemImage: "creditcard")
                                            }

                                            NavigationLink {
                                                ZeroView(mgr: mgr)
                                            } label: {
                                                Label("DirtyZero", systemImage: "doc")
                                            }
                                            
                                            if 1 == 2 {
                                                NavigationLink {
                                                    DarkBoardView()
                                                } label: {
                                                    Label("DarkBoard", systemImage: "app.badge")
                                                }
                                            }
                                            
                                            if os.majorVersion >= 26 {
                                                NavigationLink {
                                                    LGView()
                                                } label: {
                                                    Label("Liquid Glass", systemImage: "capsule")
                                                }
                                            }
                                        } header: {
                                            Text("UI Tweaks")
                                        }
                                        Section {
                                            NavigationLink {
                                                AppsView(mgr: mgr)
                                            } label: {
                                                Label("3 App Bypass", systemImage: "lock.open.fill")
                                            }
                                            NavigationLink {
                                                WhitelistView()
                                            } label: {
                                                Label("Unblacklist", systemImage: "checkmark.seal")
                                            }
                                        } header: {
                                            Text("App Management")
                                        }
                                        Section {
                                            if !showfmintabs {
                                                NavigationLink {
                                                    SantanderView(startPath: "/")
                                                } label: {
                                                    Label("File Manager", systemImage: "folder")
                                                }
                                            }

                                            NavigationLink {
                                                CustomView(mgr: mgr)
                                            } label: {
                                                Label("Custom Overwrite", systemImage: "pencil")
                                            }

                                            NavigationLink {
                                                EditorView()
                                            } label: {
                                                Label("MobileGestalt", systemImage: "gear")
                                            }

                                            NavigationLink {
                                                VarCleanView()
                                            } label: {
                                                Label("VarClean", systemImage: "sparkles")
                                            }
                                        } header: {
                                            Text("Other")
                                        }

                                        if 1 == 2 {
                                            NavigationLink("Control Center") {
                                                CCView()
                                            }

                                            NavigationLink("Passcode Theme") {
                                                PasscodeView(mgr: mgr)
                                            }
                                        }
                                    }
                                    .navigationTitle(Text("Tweaks"))
                                }
                            }
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
                                .font(.body)
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
                if !mgr.sbxready && !mgr.vfsready {
                    Text("File Manager requires Sandbox Escape or VFS. Initialise on the Home tab.")
                }
                if !mgr.dsready {
                    Text("RC File Manager requires the exploit to be run first.")
                }
            }
        }
        .navigationTitle("Files")
    }

    // MARK: - Tweaks tab

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
                        if let error = mgr.rcLastError ?? mgr.sbProc?.lastError {
                            Text("RemoteCall error: \(error)")
                                .foregroundColor(.red)
                        }
                        if RemoteCall.isLiveContainerRuntime() && !RemoteCall.isLiveProcessRuntime() {
                            Text("RemoteCall needs a PAC-enabled LiveContainer launch context. The main exploit may still work when RemoteCall is unavailable.")
                        }
                        if isdebugged() {
                            Text("Not available when a debugger is attached.")
                        }
                        Text("RemoteCall is still in development and may not work properly 100% of the time.")
                    }
                }
            }
            #endif

            // Method-specific tweaks
            if selectedmethod == .vfs && mgr.vfsready {
                vfsTweaks

            } else if selectedmethod == .sbx && mgr.sbxready {
                sbxTweaks

            } else if selectedmethod == .hybrid && mgr.vfsready && mgr.sbxready {
                hybridTweaks

            } else {
                // Nothing ready yet
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
        .navigationTitle("Tweaks")
    }

    @ViewBuilder
    private var vfsTweaks: some View {
        Section("VFS Tweaks") {
            NavigationLink("Font Overwrite") { FontPicker(mgr: mgr) }
            NavigationLink("Card Overwrite") { CardView() }
            NavigationLink("Custom Overwrite") { CustomView(mgr: mgr) }
            NavigationLink("DirtyZero (Broken)") { ZeroView(mgr: mgr) }
        }
    }

    @ViewBuilder
    private var sbxTweaks: some View {
        Section("Sandbox Tweaks") {
            NavigationLink("Card Overwrite") { CardView() }
            NavigationLink("3 App Bypass") { AppsView(mgr: mgr) }
            NavigationLink("VarClean") { VarCleanView() }
            NavigationLink("Unblacklist") { WhitelistView() }
        }
    }

    @ViewBuilder
    private var hybridTweaks: some View {
        Section("Tweaks") {
            NavigationLink("Font Overwrite") { FontPicker(mgr: mgr) }
            NavigationLink("Card Overwrite") { CardView() }
            NavigationLink("Custom Overwrite") { CustomView(mgr: mgr) }
            NavigationLink("MobileGestalt") { EditorView() }
            NavigationLink("3 App Bypass") { AppsView(mgr: mgr) }
            NavigationLink("VarClean") { VarCleanView() }
            NavigationLink("Whitelist") { WhitelistView() }
            NavigationLink("DirtyZero") { ZeroView(mgr: mgr) }

            // Hidden until ready
            if 1 == 2 {
                NavigationLink("Control Center") { CCView() }
                NavigationLink("DarkBoard") { DarkBoardView() }
                NavigationLink("Passcode Theme") { PasscodeView(mgr: mgr) }
            }
        }
    }

    // MARK: - Helpers

    private func refreshselectedmethod() {
        if let raw = UserDefaults.standard.string(forKey: "selectedmethod"),
           let m = method(rawValue: raw) {
            selectedmethod = m
        }
    }
}

// MARK: - Logs view

struct LogsView: View {
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
                    .id("logBottom")
                    .onChange(of: mgr.log) { _ in
                        if autoscroll {
                            withAnimation {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Toggle(isOn: $autoscroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .tint(autoscroll ? .blue : .secondary)

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
