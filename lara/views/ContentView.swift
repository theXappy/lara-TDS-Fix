//
//  ContentView.swift
//  lara — TDS fork
//
//  4-tab layout:
//    Tab 1  Tweaks         — fork-only features (Jetsam, Process Inspector)
//    Tab 2  Home           — verbatim upstream, not modified
//    Tab 3  File Manager   — RC FM shown directly; Lara FM reachable via toolbar
//    Tab 4  Logs           — lara operation log
//
//  Single-level NavigationStack per tab — no hub screens, no double nav bars.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("showfmintabs") private var showfmintabs: Bool = true
    @ObservedObject private var mgr = laramgr.shared
    @State private var hasoffsets     = true
    @State private var showsettings   = false
    @State private var selectedmethod: method = .hybrid
    @State private var secdRunning = false
    @State private var secdReady = false
    @State private var secdError: String? = nil
    @State private var AutoModeRunning = false
    @State private var AutoModeStep: String? = nil

    // BA2 spawn flow states
    @State private var ldRCRunning = false
    @State private var ldRCReady = false
    @State private var ldRCRetries = 0
    @State private var ldRCError: String? = nil
    @State private var ba2SpawnRunning = false
    @State private var ba2SpawnReady = false
    @State private var ba2SpawnError: String? = nil
    @State private var ba2RCRunning = false
    @State private var ba2RCReady = false
    @State private var ba2RCRetries = 0
    @State private var ba2RCError: String? = nil

    let os = ProcessInfo().operatingSystemVersion

    var body: some View {
        TabView {

            // ── Tab 1: Home ─────────────────────────────────────────────────
            NavigationStack {
                List {
                    if !hasoffsets {
                        Section("Setup") {
                            Text("Kernelcache offsets are missing. Download them in Settings.")
                                .foregroundColor(.secondary)
                            Button("Open Settings") { showsettings = true }
                        }
                    } else {
                        Section {
                            Button {
                                startAutoMode()
                            } label: {
                                if AutoModeRunning {
                                    HStack {
                                        ProgressView().progressViewStyle(.circular)
                                            .frame(width: 18, height: 18)
                                        Text(AutoModeStep ?? "Auto Mode...")
                                    }
                                } else if AutoModeComplete {
                                    HStack {
                                        Text("Auto Mode Complete")
                                        Spacer()
                                        Image(systemName: "checkmark.circle").foregroundColor(.green)
                                    }
                                } else {
                                    Text("Auto Mode")
                                }
                            }
                            .disabled(AutoModeRunning || AutoModeComplete)
                        } header: {
                            Text("Auto Mode")
                        }

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
                                Button { exit(0) } label: { Text("Detach") }
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
                                                Image(systemName: "xmark.circle").foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Initialise VFS")
                                        }
                                    } else {
                                        HStack {
                                            Text("Initialised VFS")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning)

                                if mgr.vfsready {
                                    NavigationLink("Tweaks") {
                                        List {
                                            NavigationLink("Font Overwrite") { FontPicker(mgr: mgr) }
                                            NavigationLink("Card Overwrite") { CardView() }
                                            NavigationLink("Custom Overwrite") { CustomView(mgr: mgr) }
                                            NavigationLink("DirtyZero (Broken)") { ZeroView(mgr: mgr) }
                                        }
                                        .navigationTitle("Tweaks")
                                    }
                                }

                            } else if selectedmethod == .sbx {
                                Button {
                                    mgr.sbxescape()
                                } label: {
                                    if mgr.sbxrunning {
                                        HStack {
                                            ProgressView().progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Escaping Sandbox...")
                                        }
                                    } else if !mgr.sbxready {
                                        if mgr.sbxattempted && mgr.sbxfailed {
                                            HStack {
                                                Text("SBX Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle").foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Escape Sandbox")
                                        }
                                    } else {
                                        HStack {
                                            Text("Escaped Sandbox")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)

                                if mgr.sbxready {
                                    NavigationLink("Tweaks") {
                                        List {
                                            NavigationLink("Card Overwrite") { CardView() }
                                            NavigationLink("3 App Bypass") { AppsView(mgr: mgr) }
                                            NavigationLink("VarClean") { VarCleanView() }
                                            NavigationLink("Unblacklist (Broken?)") { WhitelistView() }
                                        }
                                        .navigationTitle("Tweaks")
                                    }
                                }

                            } else { // .hybrid
                                Button {
                                    mgr.sbxescape()
                                } label: {
                                    if mgr.sbxrunning {
                                        HStack {
                                            ProgressView().progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Escaping Sandbox...")
                                        }
                                    } else if !mgr.sbxready {
                                        if mgr.sbxattempted && mgr.sbxfailed {
                                            HStack {
                                                Text("SBX Failed")
                                                Spacer()
                                                Image(systemName: "xmark.circle").foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Escape Sandbox")
                                        }
                                    } else {
                                        HStack {
                                            Text("Escaped Sandbox")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning)

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
                                                Image(systemName: "xmark.circle").foregroundColor(.red)
                                            }
                                        } else {
                                            Text("Initialise VFS")
                                        }
                                    } else {
                                        HStack {
                                            Text("Initialised VFS")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    }
                                }
                                .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning || !mgr.sbxready)

                                // ── BA2 Flow: Init lockdownd RC ──
                                Button {
                                    startLockdowndRC()
                                } label: {
                                    if ldRCRunning {
                                        HStack {
                                            ProgressView().progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Init lockdownd... #\(ldRCRetries)")
                                        }
                                    } else if ldRCReady {
                                        HStack {
                                            Text("Init RemoteCall in lockdownd")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    } else if ldRCError != nil {
                                        HStack {
                                            Text("Init RemoteCall in lockdownd")
                                                .foregroundColor(.red)
                                            Spacer()
                                            Image(systemName: "xmark.circle").foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Init RemoteCall in lockdownd")
                                    }
                                }
                                .disabled(!mgr.vfsready || ldRCReady || ldRCRunning)

                                // ── BA2 Flow: Spawn BA2 ──
                                Button {
                                    startBA2Spawn()
                                } label: {
                                    if ba2SpawnRunning {
                                        HStack {
                                            ProgressView().progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Spawning BA2...")
                                        }
                                    } else if ba2SpawnReady {
                                        HStack {
                                            Text("Spawn BA2 (lockdownd XPC)")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    } else if ba2SpawnError != nil {
                                        HStack {
                                            Text("Spawn BA2 (lockdownd XPC)")
                                                .foregroundColor(.red)
                                            Spacer()
                                            Image(systemName: "xmark.circle").foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Spawn BA2 (lockdownd XPC)")
                                    }
                                }
                                .disabled(!ldRCReady || ba2SpawnReady || ba2SpawnRunning)

                                // ── BA2 Flow: Init BA2 RC ──
                                Button {
                                    startBA2RC()
                                } label: {
                                    if ba2RCRunning {
                                        HStack {
                                            ProgressView().progressViewStyle(.circular)
                                                .frame(width: 18, height: 18)
                                            Text("Init BA2... #\(ba2RCRetries)")
                                        }
                                    } else if ba2RCReady {
                                        HStack {
                                            Text("Init RemoteCall in BackupAgent2")
                                            Spacer()
                                            Image(systemName: "checkmark.circle").foregroundColor(.green)
                                        }
                                    } else if ba2RCError != nil {
                                        HStack {
                                            Text("Init RemoteCall in BackupAgent2")
                                                .foregroundColor(.red)
                                            Spacer()
                                            Image(systemName: "xmark.circle").foregroundColor(.red)
                                        }
                                    } else {
                                        Text("Init RemoteCall in BackupAgent2")
                                    }
                                }
                                .disabled(!ba2SpawnReady || ba2RCReady || ba2RCRunning)

                            }
                        } header: {
                            Text(selectedmethod == .vfs ? "Virtual File System"
                                 : selectedmethod == .sbx ? "Sandbox Escape"
                                 : "File System Capabilities")
                        } footer: {
                            if selectedmethod == .sbx {
                                Text("Font Overwrite is only available in VFS or Hybrid mode.")
                            }
                        }

                        Section {
                            if mgr.dsready {
                                NavigationLink("Tools") { ToolsView() }
                            }

                            if mgr.vfsready && mgr.sbxready {
                                NavigationLink("Tweaks") {
                                    List {
                                        NavigationLink("Font Overwrite") { FontPicker(mgr: mgr) }
                                        NavigationLink("Card Overwrite") { CardView() }
                                        NavigationLink("Custom Overwrite") { CustomView(mgr: mgr) }
                                        NavigationLink("MobileGestalt") { EditorView() }
                                        NavigationLink("3 App Bypass") { AppsView(mgr: mgr) }
                                        NavigationLink("VarClean") { VarCleanView() }
                                        NavigationLink("Whitelist") { WhitelistView() }
                                        NavigationLink("DirtyZero") { ZeroView(mgr: mgr) }
                                    }
                                    .navigationTitle("Tweaks")
                                }
                            }

                            Button("Respring") { mgr.respring() }
                            Button("Panic!") { mgr.panic() }.disabled(!mgr.dsready)
                        } header: {
                            Text("Other")
                        }


                    }
                }
                .navigationTitle("lara")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showsettings = true } label: { Image(systemName: "gear") }
                    }
                }

            }
            .tabItem { Label("Home", systemImage: "house") }

            // ── Tab 2: Fork Tweaks ───────────────────────────────────────────
            NavigationStack {
                ForkTweaksView(mgr: mgr)
            }
            .tabItem { Label("Tweaks", systemImage: "wrench.and.screwdriver") }

            // ── Tab 3: File Manager ──────────────────────────────────────────
            NavigationStack {
                FileManagerView()
            }
            .tabItem { Label("Files", systemImage: "folder.badge.gear") }

            // ── Tab 4: Logs ──────────────────────────────────────────────────
            LogsView(logger: globallogger)
            .tabItem { Label("Logs", systemImage: "scroll") }

        } // end TabView
        .sheet(isPresented: $showsettings) {
            SettingsView(mgr: mgr, hasoffsets: $hasoffsets)
        }
        .onAppear { refreshselectedmethod() }
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

    private var AutoModeComplete: Bool {
        guard mgr.vfsready && mgr.sbxready && mgr.dsready else { return false }
        return secdReady && ba2RCReady
    }

    private func startAutoMode() {
        AutoModeRunning = true
        AutoModeStep = "Running Exploit..."

        // Step 1: Run Exploit
        offsets_init()
        mgr.run { success in
            guard success, mgr.dsready else {
                AutoModeRunning = false
                AutoModeStep = nil
                return
            }

            // Step 2: Escape Sandbox
            AutoModeStep = "Escaping Sandbox..."
            mgr.sbxescape { success in
                guard success, mgr.sbxready else {
                    AutoModeRunning = false
                    AutoModeStep = nil
                    return
                }

                // Step 3: Initialise VFS
                AutoModeStep = "Initialising VFS..."
                mgr.vfsinit { success in
                    guard success, mgr.vfsready else {
                        AutoModeRunning = false
                        AutoModeStep = nil
                        return
                    }

                    DispatchQueue.global(qos: .userInitiated).async {
                        // Steps 4-6: BA2 flow
                        do {
                            // Step 4: Init lockdownd RC
                            DispatchQueue.main.async { AutoModeStep = "Init lockdownd..." }
                            self.doLockdowndRC()
                            guard self.ldRCReady else {
                                DispatchQueue.main.async { AutoModeRunning = false; AutoModeStep = nil }
                                return
                            }

                            Thread.sleep(forTimeInterval: 0.5)

                            // Step 5: Spawn BA2
                            DispatchQueue.main.async { AutoModeStep = "Spawning BA2..." }
                            self.doBA2Spawn()
                            guard self.ba2SpawnReady else {
                                DispatchQueue.main.async { AutoModeRunning = false; AutoModeStep = nil }
                                return
                            }

                            Thread.sleep(forTimeInterval: 0.5)

                            // Step 6: Init BA2 RC
                            DispatchQueue.main.async { AutoModeStep = "Init BackupAgent2..." }
                            self.doBA2RC()
                            guard self.ba2RCReady else {
                                DispatchQueue.main.async { AutoModeRunning = false; AutoModeStep = nil }
                                return
                            }

                            Thread.sleep(forTimeInterval: 0.5)
                        }

                        // Step 7: Init securityd
                        DispatchQueue.main.async {
                            AutoModeStep = "Init securityd..."
                            secdRunning = true
                            secdError = nil
                        }
                        let rc = RemoteFileIO.shared.rcProc(for: "securityd")
                        DispatchQueue.main.async {
                            secdRunning = false
                            if rc != nil {
                                secdReady = true
                            } else {
                                secdError = "Failed to init RemoteCall in securityd"
                                AutoModeRunning = false
                                AutoModeStep = nil
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - BA2 Flow Helpers

    private func startLockdowndRC() {
        ldRCRunning = true
        ldRCRetries = 0
        ldRCError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            doLockdowndRC()
        }
    }

    private func doLockdowndRC() {
        let rcio = RemoteFileIO.shared
        var attempt = 0
        while true {
            attempt += 1
            DispatchQueue.main.async { ldRCRetries = attempt; ldRCRunning = true }
            rcio.resetProc("lockdownd")
            if let rc = rcio.rcProc(for: "lockdownd", spawnIfNeeded: false) {
                let pid = Int32(truncatingIfNeeded: rcio.callIn(rc: rc, name: "getpid", args: []))
                rcio.dbg("[AUTO] lockdownd RC success pid=\(pid) after \(attempt) attempts")
                DispatchQueue.main.async { ldRCRunning = false; ldRCReady = true }
                return
            }
            rcio.dbg("[AUTO] lockdownd RC attempt #\(attempt) failed, retrying...")
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    private func startBA2Spawn() {
        ba2SpawnRunning = true
        ba2SpawnError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            doBA2Spawn()
        }
    }

    private func doBA2Spawn() {
        let rcio = RemoteFileIO.shared
        let tag = "[AUTO][BA2-SPAWN]"
        rcio.dbg("\(tag) starting...")

        guard let rc = rcio.rcProc(for: "lockdownd", spawnIfNeeded: false) else {
            DispatchQueue.main.async { ba2SpawnRunning = false; ba2SpawnError = "lockdownd RC not ready" }
            return
        }

        let trojan = rc.trojanMem
        guard trojan != 0 else {
            DispatchQueue.main.async { ba2SpawnRunning = false; ba2SpawnError = "trojanMem=0" }
            return
        }

        func ws(_ off: UInt64, _ s: String) {
            let b = Array((s + "\0").utf8)
            b.withUnsafeBytes { rc.remote_write(trojan + off, from: $0.baseAddress, size: UInt64(b.count)) }
        }
        func wp(_ off: UInt64, _ v: UInt64) {
            var val = v
            rc.remote_write(trojan + off, from: &val, size: 8)
        }
        func ri32(_ off: UInt64) -> Int32 {
            var val: Int32 = 0
            rc.remoteRead(trojan + off, to: &val, size: 4)
            return val
        }

        // Write strings
        ws(0x000, "com.apple.lockdown.mobilebackup2")
        ws(0x080, "_LDCHECKININFO")
        ws(0x0A0, "xpc")
        ws(0x0C0, "_LDSERVICESOCK")
        ws(0x0E0, "_LDTIMESTAMP")
        ws(0x110, "com.apple.mobile.lockdown.checkin_queue")

        // socketpair
        let spRet = rcio.callIn(rc: rc, name: "socketpair", args: [1, 1, 0, trojan + 0x100])
        let fd1 = ri32(0x104)
        if spRet != 0 {
            DispatchQueue.main.async { ba2SpawnRunning = false; ba2SpawnError = "socketpair failed" }
            return
        }

        // XPC dict
        let dict = rcio.callIn(rc: rc, name: "xpc_dictionary_create", args: [0, 0, 0])
        if dict == 0 {
            DispatchQueue.main.async { ba2SpawnRunning = false; ba2SpawnError = "xpc_dictionary_create NULL" }
            return
        }

        let _ = rcio.callIn(rc: rc, name: "xpc_dictionary_set_string", args: [dict, trojan + 0x080, trojan + 0x0A0])
        let _ = rcio.callIn(rc: rc, name: "xpc_dictionary_set_fd", args: [dict, trojan + 0x0C0, UInt64(bitPattern: Int64(fd1))])
        let dateVal = rcio.callIn(rc: rc, name: "xpc_date_create_from_current", args: [])
        if dateVal != 0 {
            let ts = rcio.callIn(rc: rc, name: "xpc_date_get_value", args: [dateVal])
            let _ = rcio.callIn(rc: rc, name: "xpc_dictionary_set_date", args: [dict, trojan + 0x0E0, ts])
        }

        // XPC connection
        let conn = rcio.callIn(rc: rc, name: "xpc_connection_create_mach_service", args: [trojan + 0x000, 0, 0])
        if conn == 0 {
            DispatchQueue.main.async { ba2SpawnRunning = false; ba2SpawnError = "xpc_connection_create NULL" }
            return
        }

        let queue = rcio.callIn(rc: rc, name: "dispatch_queue_create", args: [trojan + 0x110, 0])
        if queue != 0 {
            let _ = rcio.callIn(rc: rc, name: "xpc_connection_set_target_queue", args: [conn, queue])
        }

        // Event handler block
        let pacMask: UInt64 = 0x7FFFFFFFFF
        ws(0x300, "_NSConcreteGlobalBlock")
        ws(0x340, "_NSConcreteStackBlock")
        ws(0x380, "objc_opt_self")

        var blockIsa = rcio.callIn(rc: rc, name: "dlsym", args: [UInt64(bitPattern: Int64(-2)), trojan + 0x300])
        if blockIsa == 0 {
            blockIsa = rcio.callIn(rc: rc, name: "dlsym", args: [UInt64(bitPattern: Int64(-2)), trojan + 0x340])
        }
        let blockIsaClean = blockIsa & pacMask
        let invokeRaw = rcio.callIn(rc: rc, name: "dlsym", args: [UInt64(bitPattern: Int64(-2)), trojan + 0x380])
        let invokeClean = invokeRaw & pacMask

        if blockIsaClean != 0 && invokeClean != 0 {
            wp(0x200, 0)
            wp(0x208, 0x28)
            wp(0x240, blockIsaClean)
            var flags: UInt32 = 0x50000000
            rc.remote_write(trojan + 0x248, from: &flags, size: 4)
            var reserved: UInt32 = 0
            rc.remote_write(trojan + 0x24C, from: &reserved, size: 4)
            wp(0x250, invokeClean)
            wp(0x258, trojan + 0x200)
            let _ = rcio.callIn(rc: rc, name: "xpc_connection_set_event_handler", args: [conn, trojan + 0x240])
        }

        // Resume + send
        let _ = rcio.callIn(rc: rc, name: "xpc_connection_resume", args: [conn])
        Thread.sleep(forTimeInterval: 0.1)
        let _ = rcio.callIn(rc: rc, name: "xpc_connection_send_message", args: [conn, dict])

        // Wait for BA2
        var ba2Found = false
        for _ in 1...4 {
            Thread.sleep(forTimeInterval: 0.5)
            if rcio.isRunning("BackupAgent2") {
                ba2Found = true
                break
            }
        }

        DispatchQueue.main.async {
            ba2SpawnRunning = false
            if ba2Found {
                ba2SpawnReady = true
            } else {
                ba2SpawnError = "BA2 not found in proclist after spawn"
            }
        }
    }

    private func startBA2RC() {
        ba2RCRunning = true
        ba2RCRetries = 0
        ba2RCError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            doBA2RC()
        }
    }

    private func doBA2RC() {
        let rcio = RemoteFileIO.shared
        var attempt = 0
        while true {
            attempt += 1
            DispatchQueue.main.async { ba2RCRetries = attempt; ba2RCRunning = true }
            rcio.resetProc("BackupAgent2")
            if let ba2rc = rcio.rcProc(for: "BackupAgent2", spawnIfNeeded: false) {
                let pid = Int32(truncatingIfNeeded: rcio.callIn(rc: ba2rc, name: "getpid", args: []))
                rcio.dbg("[AUTO] BA2 RC success pid=\(pid) after \(attempt) attempts")
                DispatchQueue.main.async { ba2RCRunning = false; ba2RCReady = true }
                return
            }
            rcio.dbg("[AUTO] BA2 RC attempt #\(attempt) failed, retrying...")
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

}

// MARK: - Fork Tweaks tab

/// Jetsam and Process Inspector only. Upstream tweaks remain in the Home tab.
struct ForkTweaksView: View {
    @ObservedObject var mgr: laramgr

    var body: some View {
        List {
            Section("Memory & Processes") {
                NavigationLink {
                    JetsamView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Jetsam Manager")
                            Text("Raise priority bands, set memory limits")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "memorychip")
                    }
                }

                NavigationLink {
                    ProcessInspectorView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Process Inspector")
                            Text("Browse, inspect, and manage running processes")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "cpu.fill")
                    }
                }
            }

            if !mgr.dsready {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle").foregroundColor(.secondary)
                        Text("Run the exploit on the Home tab to unlock Jetsam controls.")
                            .foregroundColor(.secondary).font(.callout)
                    }
                }
            }
        }
        .navigationTitle("Tweaks")
    }
}

// MARK: - Logs tab

struct ForkLogsView: View {
    @ObservedObject var mgr: laramgr
    @State private var autoscroll      = true
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
                    Image(systemName: autoscroll
                          ? "arrow.down.to.line.circle.fill"
                          : "arrow.down.to.line.circle")
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
