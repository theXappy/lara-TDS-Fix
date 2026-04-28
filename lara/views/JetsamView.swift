//
//  JetsamView.swift
//  lara
//
//  Jetsam memory manager.
//  Uses memorystatus_control directly (post-sbx-escape) to raise process
//  priority bands and set memory limits, preventing OOM kills.
//
//  Priority band reference:
//    0   idle / background         (killed first under pressure)
//    4   background suspended
//    5   audio background
//    8   mail / daemon
//   10   foreground app            (default)
//   12   active assertion
//   15   SpringBoard
//   16   critical daemon           (highest safe value)
//   17+  kernel protected          — never touch
//
//  Fix log (update 3):
//    • Shield icon → cpu (chip) icon in process row
//    • .alert now driven by @State bool — .constant() never fires
//    • memorystatus_control SET_JETSAM_HIGH_WATER_MARK: limit passed in flags
//      field (not as a separate buffer parameter — iOS expects UInt32 MB value)
//

import SwiftUI
import Darwin

// Declare memorystatus_control so Swift can call it without modifying the bridging header
@_silgen_name("memorystatus_control")
private func memorystatus_control(
    _ command: Int32,
    _ pid: Int32,
    _ flags: UInt32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: Int
) -> Int32

private let MEMORYSTATUS_CMD_GET_PRIORITY_LIST:           Int32 = 1
private let MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES:     Int32 = 7
private let MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK:  Int32 = 5
// Bit flag for MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK (combined with limit MB in flags):
//   0x0  → soft cap — process receives a jetsam warning, not killed
//   0x4  → hard cap — process is terminated when footprint exceeds the limit
private let MEMORYSTATUS_FLAGS_HWM_HARD: UInt32 = 0x4

// MARK: - Data model

struct JetsamProcess: Identifiable {
    let id      = UUID()
    let pid:    UInt32
    let uid:    UInt32
    let name:   String
    var targetBand:       Int  = 12
    var limitMB:          Int  = -1      // -1 = unlimited
    var terminateOnLimit: Bool = false   // true → hard kill at limit; false → soft warning
    var isProtected: Bool = false
    var origBand:    Int  = 10           // recorded before modification for restore
}

// MARK: - JetsamView

struct JetsamView: View {
    @ObservedObject private var mgr = laramgr.shared

    @State private var processes:     [JetsamProcess] = []
    @State private var loading        = false
    @State private var searchText     = ""

    // Status alert — MUST use a dedicated Bool, not .constant(status != nil),
    // which creates a read-only binding that never triggers the alert.
    @State private var statusMessage:  String = ""
    @State private var showStatus      = false

    // Editor sheet — keyed on pid, never a raw array index
    @State private var editingPID:    UInt32?
    @State private var showEditor     = false

    // Confirm restore-all
    @State private var showRestoreAll = false

    private var protectedProcesses: [JetsamProcess] {
        processes.filter { $0.isProtected }
    }

    private var filteredProcesses: [JetsamProcess] {
        let base = processes.filter { !$0.isProtected }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Body

    var body: some View {
        List {
            if !protectedProcesses.isEmpty {
                protectedSection
            }
            runningSection
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Filter processes")
        .navigationTitle("Jetsam")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !protectedProcesses.isEmpty {
                    Button("Restore All") { showRestoreAll = true }
                        .foregroundColor(.orange)
                }
                Button {
                    refresh()
                } label: {
                    if loading { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        // Use a proper Bool @State binding — .constant() never updates
        .alert("Jetsam Result", isPresented: $showStatus) {
            Button("OK") { showStatus = false }
        } message: {
            Text(statusMessage)
        }
        .alert("Restore all Jetsam changes?", isPresented: $showRestoreAll) {
            Button("Restore", role: .destructive) { restoreAll() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showEditor) {
            if let pid = editingPID,
               let idx = processes.firstIndex(where: { $0.pid == pid }) {
                EditorSheet(process: $processes[idx], onApply: { apply(pid: pid) })
            }
        }
        .onAppear { refresh() }
    }

    // MARK: - Protected section

    private var protectedSection: some View {
        Section {
            ForEach(protectedProcesses) { proc in
                HStack(spacing: 10) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        HStack(spacing: 6) {
                            Text("band \(proc.origBand) → \(proc.targetBand)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            if proc.limitMB == -1 {
                                bandTag("unlimited", .blue)
                            } else {
                                bandTag("\(proc.limitMB) MB \(proc.terminateOnLimit ? "hard" : "soft")", .orange)
                            }
                        }
                    }
                    Spacer()
                    Text("pid \(proc.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button("Restore") {
                        restore(pid: Int32(proc.pid))
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Protected (\(protectedProcesses.count))")
        } footer: {
            Text("Restore before rebooting to avoid unexpected behaviour.")
                .foregroundColor(.orange)
        }
    }

    // MARK: - Running processes section

    private var runningSection: some View {
        Section {
            if loading {
                HStack { Spacer(); ProgressView(); Text("Scanning…").foregroundColor(.secondary); Spacer() }
            } else if filteredProcesses.isEmpty {
                Text(searchText.isEmpty ? "No processes found" : "No matches")
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredProcesses.indices, id: \.self) { i in
                    processRow(filteredProcesses[i])
                }
            }
        } header: {
            HStack {
                Text(searchText.isEmpty
                     ? "Running (\(processes.count))"
                     : "Running (\(filteredProcesses.count) of \(processes.count))")
                Spacer()
                Text("R = root  M = mobile")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        } footer: {
            Text("Tap a process to set its Jetsam priority band and memory limit. Safe range: 0–16.")
        }
    }

    @ViewBuilder
    private func processRow(_ proc: JetsamProcess) -> some View {
        HStack(spacing: 10) {
            Text(proc.uid == 0 ? "R" : "M")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(proc.uid == 0 ? .orange : .secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(proc.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text("pid \(proc.pid)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Changed from "shield" to "cpu" (processor chip icon) — update 3 request
            Image(systemName: "cpu")
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingPID = proc.pid
            showEditor = true
        }
        .disabled(!mgr.dsready && !mgr.sbxready)
    }

    // MARK: - Editor sheet

    struct EditorSheet: View {
        @Binding var process: JetsamProcess
        let onApply: () -> Void
        @Environment(\.dismiss) private var dismiss

        @State private var bandDouble:       Double = 12
        @State private var limitDouble:      Double = -1
        @State private var terminateOnLimit: Bool   = false

        private let bandMarkers: [(Int, String)] = [
            (0,  "idle"), (4, "bg suspend"), (5, "bg audio"),
            (8,  "daemon"), (10, "foreground"), (12, "assertion"),
            (15, "SpringBoard"), (16, "critical — max safe")
        ]

        var body: some View {
            NavigationView {
                List {
                    Section("Process") {
                        LabeledContent("Name", value: process.name)
                        LabeledContent("PID",  value: "\(process.pid)")
                        LabeledContent("UID",  value: "\(process.uid) (\(process.uid == 0 ? "root" : "mobile"))")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Band")
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text("\(Int(bandDouble))  · \(bandLabel(Int(bandDouble)))")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(bandColour(Int(bandDouble)))
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $bandDouble, in: 0...16, step: 1)
                                .tint(bandColour(Int(bandDouble)))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(bandMarkers, id: \.0) { band, label in
                                        Button("\(band)") { bandDouble = Double(band) }
                                            .font(.system(size: 10, design: .monospaced))
                                            .buttonStyle(.bordered)
                                            .tint(Int(bandDouble) == band ? bandColour(band) : .secondary)
                                            .controlSize(.mini)
                                    }
                                }
                            }
                        }
                    } header: { Text("Priority Band") }
                    footer: { Text("Foreground apps sit at band 10. SpringBoard is 15. Do not exceed 16.") }

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Memory Limit")
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(limitDouble < 0 ? "Unlimited" : "\(Int(limitDouble)) MB")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(limitDouble < 0 ? .blue : .orange)
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $limitDouble, in: -1...2048, step: 1)
                                .tint(limitDouble < 0 ? .blue : .orange)
                            Toggle("Unlimited (no cap)", isOn: Binding(
                                get: { limitDouble < 0 },
                                set: { limitDouble = $0 ? -1 : 512 }
                            ))
                            Divider()
                            Toggle(isOn: $terminateOnLimit) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Terminate process on limit reached")
                                        .font(.system(.body, design: .monospaced))
                                    Text(terminateOnLimit
                                         ? "Hard cap — process is killed when footprint exceeds limit"
                                         : "Soft cap — process receives a jetsam warning, not killed")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(terminateOnLimit ? .red : .secondary)
                                }
                            }
                            .disabled(limitDouble < 0)
                        }
                    } header: { Text("Memory Limit") }
                    footer: { Text("Unlimited removes the per-process footprint cap. A specific limit caps a runaway process.") }

                    Section {
                        Button {
                            process.targetBand       = Int(bandDouble)
                            process.limitMB          = Int(limitDouble)
                            process.terminateOnLimit = terminateOnLimit
                            onApply()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Apply Jetsam Policy", systemImage: "cpu")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .foregroundColor(.white)
                        .listRowBackground(Color.blue)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(process.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onAppear {
                    bandDouble       = Double(process.targetBand)
                    limitDouble      = Double(process.limitMB)
                    terminateOnLimit = process.terminateOnLimit
                }
            }
        }

        private func bandLabel(_ b: Int) -> String {
            bandMarkers.last(where: { $0.0 <= b })?.1 ?? "?"
        }

        private func bandColour(_ b: Int) -> Color {
            switch b {
            case 0...4:   return .red
            case 5...9:   return .orange
            case 10...12: return .green
            case 13...15: return .blue
            default:      return .purple
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: [JetsamProcess] = []
            DispatchQueue.main.async {
                self.processes = result
                self.loading   = false
            }
        }
    }

    private func apply(pid: UInt32) {
        guard let idx = processes.firstIndex(where: { $0.pid == pid }) else { return }
        let proc    = processes[idx]
        let band    = Int32(proc.targetBand)
        let limitMB = Int32(proc.limitMB)

        // Set priority band
        let bandOK = setJetsamBand(pid: Int32(proc.pid), band: band)

        // Set memory limit.
        // iOS memorystatus_control SET_JETSAM_HIGH_WATER_MARK:
        //   flags = (limit_in_MB as UInt32) | MEMORYSTATUS_FLAGS_HWM_HARD (if hard kill desired)
        // The limit value is packed INTO the flags field — not a separate buffer.
        var limitOK = true
        if limitMB > 0 {
            // Soft or hard cap
            let flags: UInt32 = UInt32(limitMB) | (proc.terminateOnLimit ? MEMORYSTATUS_FLAGS_HWM_HARD : 0)
            let ret = memorystatus_control(
                MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK,
                Int32(proc.pid),
                flags,
                nil,
                0
            )
            limitOK = ret == 0
        }
        // When limitMB == -1 (unlimited) we skip — there's no standard command
        // to clear an HWM; the process retains existing or system-default limit.

        processes[idx].isProtected = bandOK
        processes[idx].origBand    = bandOK ? proc.origBand : proc.origBand

        let limitDesc: String
        if limitMB == -1 {
            limitDesc = ", memory: system default"
        } else if limitMB > 0 {
            limitDesc = ", \(limitMB) MB (\(proc.terminateOnLimit ? "hard kill" : "soft warn")) \(limitOK ? "✓" : "⚠ failed")"
        } else {
            limitDesc = ""
        }

        if bandOK {
            statusMessage = "Protected \(proc.name) → band \(band)\(limitDesc)"
        } else {
            statusMessage = "memorystatus_control failed for \(proc.name) (pid \(proc.pid)) — sbx escape may be required"
        }
        showStatus = true   // triggers .alert($showStatus) — this works, .constant() does not
    }

    private func restore(pid: Int32) {
        guard let idx = processes.firstIndex(where: { $0.pid == UInt32(pid) }) else { return }
        let proc = processes[idx]
        _ = setJetsamBand(pid: pid, band: Int32(proc.origBand))
        processes[idx].isProtected = false
        statusMessage = "Restored \(proc.name) to band \(proc.origBand)"
        showStatus    = true
    }

    private func restoreAll() {
        for proc in protectedProcesses {
            _ = setJetsamBand(pid: Int32(proc.pid), band: Int32(proc.origBand))
            if let idx = processes.firstIndex(where: { $0.pid == proc.pid }) {
                processes[idx].isProtected = false
            }
        }
        statusMessage = "All Jetsam changes restored"
        showStatus    = true
    }

    // MARK: - memorystatus_control wrapper

    private func setJetsamBand(pid: Int32, band: Int32) -> Bool {
        // memorystatus_priority_properties_t:
        //   int32_t  priority   (offset 0)
        //   uint64_t user_data  (offset 8, natural alignment)
        // Total: 16 bytes
        var buf = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: band) { src in
            buf.replaceSubrange(0..<4, with: src)
        }
        let ret = buf.withUnsafeMutableBytes { ptr in
            memorystatus_control(
                MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES,
                pid,
                0,
                ptr.baseAddress,
                16
            )
        }
        return ret == 0
    }

    // MARK: - Band helpers (row display)

    private func bandColour(_ b: Int) -> Color {
        switch b {
        case 0...4:   return .red
        case 5...9:   return .orange
        case 10...12: return .green
        case 13...15: return .blue
        default:      return .purple
        }
    }

    @ViewBuilder
    private func bandTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.3), lineWidth: 0.5))
            )
    }
}
