//
//  BA2SpawnTestView.swift
//  lara — TDS fork
//
//  Test harness for launching BackupAgent2 from lockdownd — the ONLY
//  supported path (as Apple intended via XPC mach service activation).
//
//  Key findings from lockdownd RE (Ghidra, FUN_1000227a8 "spawn_xpc_service"):
//    1. Dict is created FIRST (before connection) — xpc_dictionary_create(0,0,0)
//    2. Dict keys: _LDCHECKININFO="xpc", _LDTIMESTAMP, _LDCHECKINDICT, _LDSERVICESOCK=fd
//    3. A socket fd is passed via _LDSERVICESOCK (BA2 needs it to talk to iTunes)
//    4. xpc_connection_create_mach_service("com.apple.lockdown.mobilebackup2", 0, 0)
//    5. dispatch_queue_create + xpc_connection_set_target_queue
//    6. xpc_connection_set_event_handler (REQUIRED — XPC won't work without it)
//    7. xpc_connection_resume — triggers launchd to spawn BackupAgent2
//    8. xpc_connection_send_message(conn, dict) — delivers the checkin + socket
//
//  Critical insight: our previous test called resume BEFORE creating the dict,
//  which destabilized the RC trojan (async XPC activity corrupts the thread).
//  Fix: create everything first, then resume+send as the final steps.
//

import SwiftUI

struct BA2SpawnTestView: View {
    @ObservedObject private var mgr = laramgr.shared
    private let rcio = RemoteFileIO.shared

    @State private var ldStatus: SpawnStatus = .idle
    @State private var ldDetail: String = ""
    @State private var ldRetries: Int = 0
    @State private var ldRetrying: Bool = false

    @State private var spawnStatus: SpawnStatus = .idle
    @State private var spawnDetail: String = ""

    @State private var ba2RCStatus: SpawnStatus = .idle
    @State private var ba2RCDetail: String = ""
    @State private var ba2RCRetries: Int = 0
    @State private var ba2RCRetrying: Bool = false

    enum SpawnStatus {
        case idle, running, success, failed
    }

    var body: some View {
        List {
            // ─── RC Init ─────────────────────────────────────────────
            Section {
                statusButton("Init RC → lockdownd", status: ldStatus, detail: ldDetail) {
                    initRC(statusBinding: $ldStatus, detailBinding: $ldDetail)
                }
                if ldRetrying {
                    HStack {
                        ProgressView().progressViewStyle(.circular).frame(width: 12, height: 12)
                        Text("Retrying... attempt #\(ldRetries)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else if ldStatus == .success && ldRetries > 0 {
                    Text("Succeeded after \(ldRetries) attempts")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } header: {
                Text("Step 1: RC into lockdownd")
            } footer: {
                Text("lockdownd (root, pid varies) is the ONLY process that should spawn BackupAgent2 via XPC.")
            }

            // ─── Spawn (lockdownd's exact flow) ──────────────────────
            Section {
                statusButton("Spawn BA2 (lockdownd XPC flow)", status: spawnStatus, detail: spawnDetail) {
                    spawnBA2(statusBinding: $spawnStatus, detailBinding: $spawnDetail)
                }
                .disabled(ldStatus != .success)
            } header: {
                Text("Step 2: XPC Spawn (lockdownd's exact flow)")
            } footer: {
                Text("Replicates lockdownd's spawn_xpc_service: dict first, then connection+resume+send. Passes a real socket FD so BA2 won't exit immediately.")
            }

            // ─── BA2 RC Init ─────────────────────────────────────────────
            if spawnStatus == .success {
                Section {
                    statusButton("Init RC → BackupAgent2", status: ba2RCStatus, detail: ba2RCDetail) {
                        initBA2RC()
                    }
                    if ba2RCRetrying {
                        HStack {
                            ProgressView().progressViewStyle(.circular).frame(width: 12, height: 12)
                            Text("Retrying... attempt #\(ba2RCRetries)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else if ba2RCStatus == .success && ba2RCRetries > 0 {
                        Text("Succeeded after \(ba2RCRetries) attempts")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Step 3: RC into BackupAgent2")
                } footer: {
                    Text("Infinite retry until RC attaches to the newly spawned BA2 process.")
                }
            }

            // ─── Diagnostics ─────────────────────────────────────────
            Section {
                Button("Check if BackupAgent2 is running") {
                    let running = rcio.isRunning("BackupAgent2")
                    let procs = rcio.listRunningProcesses()
                    let backupRelated = procs.filter {
                        $0.name.lowercased().contains("backup") || $0.name.contains("BA2") || $0.name.contains("BackupAgent")
                    }
                    let msg = running
                        ? "YES — BackupAgent2 found in proclist"
                        : "NO — not found. Related: \(backupRelated.map { "\($0.name)(\($0.pid))" }.joined(separator: ", ").isEmpty ? "none" : backupRelated.map { "\($0.name)(\($0.pid))" }.joined(separator: ", "))"
                    rcio.dbg("[BA2-TEST] isRunning check: \(msg)")
                    mgr.logmsg("[BA2-TEST] \(msg)")
                }

                Button("Dump all processes (to logs)") {
                    let procs = rcio.listRunningProcesses()
                    rcio.dbg("[BA2-TEST] === FULL PROCESS LIST (\(procs.count) procs) ===")
                    for p in procs {
                        rcio.dbg("[BA2-TEST]   pid=\(p.pid) uid=\(p.uid) name=\(p.name)")
                    }
                    rcio.dbg("[BA2-TEST] === END PROCESS LIST ===")
                    mgr.logmsg("[BA2-TEST] Dumped \(procs.count) processes to logs")
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .navigationTitle("BA2 Spawn Test")
    }

    // MARK: - UI Helpers

    @ViewBuilder
    private func statusButton(_ title: String, status: SpawnStatus, detail: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: action) {
                HStack {
                    Text(title)
                    Spacer()
                    switch status {
                    case .idle:
                        EmptyView()
                    case .running:
                        ProgressView().progressViewStyle(.circular).frame(width: 16, height: 16)
                    case .success:
                        Image(systemName: "checkmark.circle").foregroundColor(.green)
                    case .failed:
                        Image(systemName: "xmark.circle").foregroundColor(.red)
                    }
                }
            }
            .disabled(status == .running)

            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(status == .failed ? .red : status == .success ? .green : .secondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - RC Init (infinite retry)

    private func initRC(statusBinding: Binding<SpawnStatus>, detailBinding: Binding<String>) {
        statusBinding.wrappedValue = .running
        detailBinding.wrappedValue = "Starting..."
        ldRetries = 0
        ldRetrying = true
        rcio.dbg("[BA2-TEST] ═══ INIT RC for lockdownd (infinite retry) ═══")

        DispatchQueue.global(qos: .userInitiated).async {
            var attempt = 0
            while true {
                attempt += 1
                DispatchQueue.main.async {
                    ldRetries = attempt
                    detailBinding.wrappedValue = "Attempt #\(attempt)..."
                }
                rcio.dbg("[BA2-TEST] lockdownd RC attempt #\(attempt)")

                // Reset pool state so rcProc doesn't early-return nil on "failed" from previous attempt
                rcio.resetProc("lockdownd")

                if let rc = rcio.rcProc(for: "lockdownd", spawnIfNeeded: false) {
                    let pid = Int32(truncatingIfNeeded: rcio.callIn(rc: rc, name: "getpid", args: []))
                    rcio.dbg("[BA2-TEST] RC init SUCCESS for lockdownd pid=\(pid) after \(attempt) attempts")
                    DispatchQueue.main.async {
                        ldRetrying = false
                        statusBinding.wrappedValue = .success
                        detailBinding.wrappedValue = "Ready (pid=\(pid)) — took \(attempt) attempt\(attempt > 1 ? "s" : "")"
                    }
                    return
                }

                rcio.dbg("[BA2-TEST] lockdownd RC attempt #\(attempt) failed, retrying in 1s...")
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }

    // MARK: - Spawn BA2 (lockdownd's exact XPC flow)

    /// Replicates lockdownd's FUN_1000227a8 (spawn_xpc_service) exactly:
    ///   1. Create socketpair (so BA2 has a valid fd and won't exit immediately)
    ///   2. Create XPC dict (BEFORE connection — avoids RC trojan destabilization)
    ///   3. Fill dict with _LDCHECKININFO, _LDSERVICESOCK
    ///   4. xpc_connection_create_mach_service
    ///   5. xpc_connection_set_event_handler (dummy — but XPC requires one)
    ///   6. xpc_connection_resume
    ///   7. xpc_connection_send_message
    private func spawnBA2(statusBinding: Binding<SpawnStatus>, detailBinding: Binding<String>) {
        statusBinding.wrappedValue = .running
        detailBinding.wrappedValue = "Spawning BA2 via lockdownd XPC flow..."
        let tag = "[BA2-TEST][LOCKDOWND-XPC]"
        rcio.dbg("\(tag) ═══ START ═══")

        DispatchQueue.global(qos: .userInitiated).async {
            guard let rc = rcio.rcProc(for: "lockdownd", spawnIfNeeded: false) else {
                finish(statusBinding, detailBinding, .failed, "lockdownd RC not ready", tag)
                return
            }

            let trojan = rc.trojanMem
            guard trojan != 0 else {
                finish(statusBinding, detailBinding, .failed, "trojanMem=0", tag)
                return
            }
            rcio.dbg("\(tag) trojan=0x\(String(trojan, radix: 16))")

            // ── Memory layout in trojan region ──
            // 0x000: XPC service name C-string
            // 0x080: "_LDCHECKININFO" key
            // 0x0A0: "xpc" value
            // 0x0C0: "_LDSERVICESOCK" key
            // 0x0E0: "_LDTIMESTAMP" key
            // 0x100: socketpair fds [int, int] (8 bytes)
            // 0x110: "com.apple.mobile.lockdown.checkin_queue" (queue name)
            // 0x200: block descriptor (size=0x28): reserved, size, [copy, dispose]
            // 0x240: block literal (size=0x28): isa, flags, reserved, invoke, descriptor

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

            // Write all strings up front
            ws(0x000, "com.apple.lockdown.mobilebackup2")
            ws(0x080, "_LDCHECKININFO")
            ws(0x0A0, "xpc")
            ws(0x0C0, "_LDSERVICESOCK")
            ws(0x0E0, "_LDTIMESTAMP")
            ws(0x110, "com.apple.mobile.lockdown.checkin_queue")
            rcio.dbg("\(tag) strings written to trojan memory")

            // ── Step 1: Create a socketpair so BA2 has a valid fd ──
            // socketpair(AF_UNIX=1, SOCK_STREAM=1, 0, &sv)
            let spRet = rcio.callIn(rc: rc, name: "socketpair", args: [1, 1, 0, trojan + 0x100])
            let fd0 = ri32(0x100)
            let fd1 = ri32(0x104)
            rcio.dbg("\(tag) socketpair ret=\(spRet) fds=[\(fd0), \(fd1)]")
            if spRet != 0 {
                finish(statusBinding, detailBinding, .failed, "socketpair failed ret=\(spRet)", tag)
                return
            }

            // ── Step 2: Create the XPC dictionary FIRST ──
            // This MUST happen before xpc_connection_resume to avoid RC destabilization
            let dict = rcio.callIn(rc: rc, name: "xpc_dictionary_create", args: [0, 0, 0])
            rcio.dbg("\(tag) xpc_dictionary_create → 0x\(String(dict, radix: 16))")
            if dict == 0 {
                finish(statusBinding, detailBinding, .failed, "xpc_dictionary_create returned NULL", tag)
                return
            }

            // ── Step 3: Fill the dict exactly like lockdownd does ──
            // _LDCHECKININFO = "xpc"
            let _ = rcio.callIn(rc: rc, name: "xpc_dictionary_set_string", args: [dict, trojan + 0x080, trojan + 0x0A0])
            rcio.dbg("\(tag) set _LDCHECKININFO=xpc")

            // _LDSERVICESOCK = fd1 (pass one end of socketpair to BA2)
            let _ = rcio.callIn(rc: rc, name: "xpc_dictionary_set_fd", args: [dict, trojan + 0x0C0, UInt64(bitPattern: Int64(fd1))])
            rcio.dbg("\(tag) set _LDSERVICESOCK=fd\(fd1)")

            // _LDTIMESTAMP — get current time
            let dateVal = rcio.callIn(rc: rc, name: "xpc_date_create_from_current", args: [])
            if dateVal != 0 {
                let ts = rcio.callIn(rc: rc, name: "xpc_date_get_value", args: [dateVal])
                let _ = rcio.callIn(rc: rc, name: "xpc_dictionary_set_date", args: [dict, trojan + 0x0E0, ts])
                rcio.dbg("\(tag) set _LDTIMESTAMP=\(ts)")
            } else {
                rcio.dbg("\(tag) xpc_date_create_from_current returned NULL (non-fatal)")
            }

            // ── Step 4: Create the XPC connection ──
            let conn = rcio.callIn(rc: rc, name: "xpc_connection_create_mach_service", args: [trojan + 0x000, 0, 0])
            rcio.dbg("\(tag) xpc_connection_create_mach_service → 0x\(String(conn, radix: 16))")
            if conn == 0 {
                finish(statusBinding, detailBinding, .failed, "xpc_connection_create_mach_service returned NULL", tag)
                return
            }

            // ── Step 5: Create dispatch queue + set as target ──
            let queue = rcio.callIn(rc: rc, name: "dispatch_queue_create", args: [trojan + 0x110, 0])
            rcio.dbg("\(tag) dispatch_queue_create → 0x\(String(queue, radix: 16))")
            if queue != 0 {
                let _ = rcio.callIn(rc: rc, name: "xpc_connection_set_target_queue", args: [conn, queue])
                rcio.dbg("\(tag) xpc_connection_set_target_queue set")
            }

            // ── Step 6: Set event handler ──
            // XPC REQUIRES an event handler before resume. Without it, the connection
            // is invalid and launchd won't spawn the service.
            //
            // Block layout (ARM64):
            //   +0x00: isa (8 bytes) — pointer to block class
            //   +0x08: flags (4 bytes) + reserved (4 bytes)
            //   +0x10: invoke (8 bytes) — function pointer: void(*)(block, event)
            //   +0x18: descriptor (8 bytes) — pointer to descriptor struct
            // Descriptor:
            //   +0x00: reserved (8 bytes)
            //   +0x08: size (8 bytes) — sizeof(block literal)
            //
            // FIXES from previous attempt:
            //   - dlsym name: "_NSConcreteGlobalBlock" (single underscore, NOT double)
            //   - Write strings BEFORE calling dlsym (not after!)
            //   - Strip PAC bits from returned pointers (T1SZ=25 → mask=0x7FFFFFFFFF)

            let pacMask: UInt64 = 0x7FFFFFFFFF  // 39-bit VA for T1SZ=25

            // Write dlsym lookup strings FIRST
            ws(0x300, "_NSConcreteGlobalBlock")    // SINGLE underscore for dlsym!
            ws(0x340, "_NSConcreteStackBlock")     // fallback
            ws(0x380, "objc_opt_self")             // noop invoke function

            // Look up _NSConcreteGlobalBlock (the block ISA class)
            var blockIsa = rcio.callIn(rc: rc, name: "dlsym", args: [UInt64(bitPattern: Int64(-2)), trojan + 0x300])
            rcio.dbg("\(tag) dlsym(_NSConcreteGlobalBlock) raw=0x\(String(blockIsa, radix: 16))")
            if blockIsa == 0 {
                // Try stack block as fallback
                blockIsa = rcio.callIn(rc: rc, name: "dlsym", args: [UInt64(bitPattern: Int64(-2)), trojan + 0x340])
                rcio.dbg("\(tag) dlsym(_NSConcreteStackBlock) fallback raw=0x\(String(blockIsa, radix: 16))")
            }
            // dlsym for data symbols returns the ADDRESS of the variable, not a code pointer
            // so it should NOT have PAC bits — but strip just in case
            let blockIsaClean = blockIsa & pacMask
            rcio.dbg("\(tag) blockIsa clean=0x\(String(blockIsaClean, radix: 16))")

            // Look up objc_opt_self as a harmless invoke (takes id, returns id — ignores extra args on ARM64)
            let invokeRaw = rcio.callIn(rc: rc, name: "dlsym", args: [UInt64(bitPattern: Int64(-2)), trojan + 0x380])
            let invokeClean = invokeRaw & pacMask
            rcio.dbg("\(tag) dlsym(objc_opt_self) raw=0x\(String(invokeRaw, radix: 16)) clean=0x\(String(invokeClean, radix: 16))")

            if blockIsaClean != 0 && invokeClean != 0 {
                // Write block descriptor at trojan+0x200
                wp(0x200, 0)            // reserved
                wp(0x208, 0x28)         // size = 40 bytes (5 fields × 8)

                // Write block literal at trojan+0x240
                // For global blocks: isa points to _NSConcreteGlobalBlock,
                // flags has BLOCK_IS_GLOBAL (bit 28) set
                wp(0x240, blockIsaClean)    // isa
                var flags: UInt32 = 0x50000000  // BLOCK_IS_GLOBAL=0x10000000 | BLOCK_HAS_DESCRIPTOR=0x40000000
                rc.remote_write(trojan + 0x248, from: &flags, size: 4)
                var reserved: UInt32 = 0
                rc.remote_write(trojan + 0x24C, from: &reserved, size: 4)
                wp(0x250, invokeClean)      // invoke (stripped of PAC)
                wp(0x258, trojan + 0x200)   // descriptor

                rcio.dbg("\(tag) block at 0x\(String(trojan + 0x240, radix: 16)): isa=0x\(String(blockIsaClean, radix: 16)) invoke=0x\(String(invokeClean, radix: 16)) desc=0x\(String(trojan + 0x200, radix: 16))")

                let _ = rcio.callIn(rc: rc, name: "xpc_connection_set_event_handler", args: [conn, trojan + 0x240])
                rcio.dbg("\(tag) xpc_connection_set_event_handler SET")
            } else {
                rcio.dbg("\(tag) CRITICAL: cannot construct block! blockIsa=0x\(String(blockIsa, radix: 16)) invoke=0x\(String(invokeRaw, radix: 16))")
                rcio.dbg("\(tag) Trying without event handler (will likely fail)...")
            }

            // Verify lockdownd is still alive before resume
            let pidCheck1 = Int32(truncatingIfNeeded: rcio.callIn(rc: rc, name: "getpid", args: []))
            rcio.dbg("\(tag) pre-resume lockdownd pid check: \(pidCheck1)")

            // ── Step 7: Resume the connection ──
            let _ = rcio.callIn(rc: rc, name: "xpc_connection_resume", args: [conn])
            rcio.dbg("\(tag) xpc_connection_resume called")

            // Small delay to let XPC runtime process the resume
            Thread.sleep(forTimeInterval: 0.1)

            // Verify lockdownd is still alive after resume
            let pidCheck2 = Int32(truncatingIfNeeded: rcio.callIn(rc: rc, name: "getpid", args: []))
            rcio.dbg("\(tag) post-resume lockdownd pid check: \(pidCheck2)")

            // ── Step 8: Send the checkin message ──
            let _ = rcio.callIn(rc: rc, name: "xpc_connection_send_message", args: [conn, dict])
            rcio.dbg("\(tag) xpc_connection_send_message sent")

            // Verify lockdownd STILL alive after send
            let pidCheck3 = Int32(truncatingIfNeeded: rcio.callIn(rc: rc, name: "getpid", args: []))
            rcio.dbg("\(tag) post-send lockdownd pid check: \(pidCheck3)")

            // ── Wait for launchd to spawn BA2 ──
            // Check multiple times with short intervals
            rcio.dbg("\(tag) waiting for BA2 spawn...")
            var ba2Found = false
            for i in 1...4 {
                Thread.sleep(forTimeInterval: 0.5)
                if rcio.isRunning("BackupAgent2") {
                    ba2Found = true
                    rcio.dbg("\(tag) BA2 detected after \(i * 500)ms!")
                    break
                }
                rcio.dbg("\(tag) check \(i)/4: BA2 not yet in proclist")
            }

            // ── Check if BackupAgent2 appeared ──
            if ba2Found {
                rcio.dbg("\(tag) BA2 is alive! Spawn step complete.")
                finish(statusBinding, detailBinding, .success, "BA2 spawned! Use Step 3 to RC attach.", tag)
            } else {
                // Detailed failure info
                let procs = rcio.listRunningProcesses()
                let partial = procs.filter { $0.name.lowercased().contains("backup") }
                let lockdowns = procs.filter { $0.name == "lockdownd" }
                rcio.dbg("\(tag) lockdownd pids in proclist: \(lockdowns.map { "\($0.pid)" }.joined(separator: ","))")
                rcio.dbg("\(tag) backup-related in proclist: \(partial.map { "\($0.name)(\($0.pid))" }.joined(separator: ", "))")
                rcio.dbg("\(tag) RC lockdownd pid was: \(pidCheck1), post-resume: \(pidCheck2), post-send: \(pidCheck3)")
                let detail: String
                if partial.isEmpty {
                    detail = "Not in proclist. ld_pids=\(lockdowns.map{"\($0.pid)"}.joined(separator:",")) rc_pid=\(pidCheck1)/\(pidCheck2)/\(pidCheck3)"
                } else {
                    detail = "Partial: \(partial.map { "\($0.name)(\($0.pid))" }.joined(separator: ", "))"
                }
                finish(statusBinding, detailBinding, .failed, detail, tag)
            }
        }
    }

    // MARK: - BA2 RC Init (infinite retry)

    private func initBA2RC() {
        ba2RCStatus = .running
        ba2RCDetail = "Starting..."
        ba2RCRetries = 0
        ba2RCRetrying = true
        rcio.dbg("[BA2-TEST] ═══ INIT RC for BackupAgent2 (infinite retry) ═══")

        DispatchQueue.global(qos: .userInitiated).async {
            var attempt = 0
            while true {
                attempt += 1
                DispatchQueue.main.async {
                    ba2RCRetries = attempt
                    ba2RCDetail = "Attempt #\(attempt)..."
                }
                rcio.dbg("[BA2-TEST] BA2 RC attempt #\(attempt)")

                // Reset pool state so rcProc doesn't early-return nil on "failed"
                rcio.resetProc("BackupAgent2")

                // Use rcProc so the RC gets registered in the pool —
                // otherwise the filesystem view won't see it as ready
                if let ba2rc = rcio.rcProc(for: "BackupAgent2", spawnIfNeeded: false) {
                    let pid = Int32(truncatingIfNeeded: rcio.callIn(rc: ba2rc, name: "getpid", args: []))
                    rcio.dbg("[BA2-TEST] BA2 RC init SUCCESS pid=\(pid) after \(attempt) attempts (registered in pool)")
                    DispatchQueue.main.async {
                        ba2RCRetrying = false
                        ba2RCStatus = .success
                        ba2RCDetail = "Attached! (pid=\(pid)) — took \(attempt) attempt\(attempt > 1 ? "s" : "")"
                    }
                    return
                }

                // Check if BA2 is still alive
                if !rcio.isRunning("BackupAgent2") {
                    rcio.dbg("[BA2-TEST] BA2 RC attempt #\(attempt): BA2 no longer in proclist!")
                    DispatchQueue.main.async {
                        ba2RCDetail = "Attempt #\(attempt) — BA2 died, still retrying..."
                    }
                }

                rcio.dbg("[BA2-TEST] BA2 RC attempt #\(attempt) failed, retrying in 1s...")
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }

    // MARK: - Helpers

    private func finish(_ statusBinding: Binding<SpawnStatus>, _ detailBinding: Binding<String>, _ status: SpawnStatus, _ detail: String, _ tag: String) {
        rcio.dbg("\(tag) RESULT: \(status == .success ? "SUCCESS" : "FAILED") — \(detail)")
        DispatchQueue.main.async {
            statusBinding.wrappedValue = status
            detailBinding.wrappedValue = detail
        }
    }
}
