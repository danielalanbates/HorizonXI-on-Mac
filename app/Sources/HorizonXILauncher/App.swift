import SwiftUI
import AppKit

@main
struct HorizonXILauncherApp: App {
    var body: some Scene {
        WindowGroup("HorizonXI on Mac") {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @State private var installs: [Install] = []
    @State private var selected: Install?
    @State private var checks: [Check] = []
    @State private var perf = PerfSettings.load()
    @StateObject private var runner = Runner()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                ScrollView { checklist.padding(14) }.frame(minWidth: 320)
                VStack(spacing: 0) {
                    perfPane.padding(14)
                    Divider()
                    logPane
                }.frame(minWidth: 340)
            }
            Divider()
            footer
        }
        .onAppear(perform: refresh)
    }

    // MARK: - Panes

    private var header: some View {
        HStack(spacing: 10) {
            Text("HorizonXI on Mac").font(.headline)
            Picker("", selection: Binding(
                get: { selected?.id ?? "" },
                set: { id in selected = installs.first { $0.id == id }; recheck() })
            ) {
                ForEach(installs) { i in
                    Text("\(i.wrapper.lastPathComponent) · \(i.prefixName)").tag(i.id)
                }
                if installs.isEmpty { Text("no install found").tag("") }
            }
            .labelsHidden()
            .frame(maxWidth: 340)
            Button("Rescan", action: refresh)
            Spacer()
        }
        .padding(10)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preflight").font(.subheadline).bold()
            if checks.isEmpty {
                Text("No wine wrapper with a HorizonXI client was found.\nMount the drive holding siku.app and press Rescan.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(checks) { c in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(c.state)).foregroundStyle(color(c.state))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title)
                        Text(c.detail).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var perfPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Performance").font(.subheadline).bold()
            Toggle("msync (fast synchronisation)", isOn: $perf.msync)
            Toggle("esync (only if msync is off)", isOn: $perf.esync).disabled(perf.msync)
            Toggle("Silence wine debug channels", isOn: $perf.silenceWineDebug)
            Toggle("Keep awake (disable App Nap)", isOn: $perf.disableAppNap)
            Toggle("Large address aware", isOn: $perf.largeAddressAware)
            Toggle("Metal HUD (measure FPS)", isOn: $perf.metalHUD)
            HStack {
                Button("Open FFXI Config") { openFFXIConfig() }
                    .disabled(selected == nil)
                Text("in-game resolution / detail live here")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: perf.msync) { _ in perf.save() }
        .onChange(of: perf.esync) { _ in perf.save() }
        .onChange(of: perf.silenceWineDebug) { _ in perf.save() }
        .onChange(of: perf.disableAppNap) { _ in perf.save() }
        .onChange(of: perf.largeAddressAware) { _ in perf.save() }
        .onChange(of: perf.metalHUD) { _ in perf.save() }
    }

    private var logPane: some View {
        ScrollViewReader { sp in
            ScrollView {
                Text(runner.log.isEmpty ? "—" : runner.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .id("end")
            }
            .onChange(of: runner.log) { _ in sp.scrollTo("end", anchor: .bottom) }
        }
    }

    private var footer: some View {
        HStack {
            Button("Repair prefix") { if let i = selected { runner.repair(i) } }
                .disabled(selected == nil || runner.busy)
            Spacer()
            if runner.running {
                Button("Stop") { if let i = selected { runner.stop(i) } }
            }
            Button(runner.running ? "Running…" : "Play") {
                if let i = selected { runner.launch(i, perf: perf) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil || runner.running || checks.contains { $0.state == .bad })
        }
        .padding(10)
    }

    // MARK: - Actions

    private func refresh() {
        installs = Install.discover()
        if selected == nil || !installs.contains(where: { $0.id == selected?.id }) {
            selected = installs.first
        }
        recheck()
    }

    private func recheck() {
        checks = selected.map { Preflight.run($0) } ?? []
    }

    private func openFFXIConfig() {
        guard let i = selected else { return }
        let p = Process()
        p.executableURL = i.wine
        p.arguments = ["C:\\HorizonXI\\SquareEnix\\FINAL FANTASY XI\\FINAL FANTASY XI Config.exe"]
        p.currentDirectoryURL = i.gameDir
        var e = ProcessInfo.processInfo.environment
        for (k, v) in perf.environment(for: i) { e[k] = v }
        p.environment = e
        try? p.run()
    }

    private func icon(_ s: Check.State) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        }
    }

    private func color(_ s: Check.State) -> Color {
        switch s {
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }
}
