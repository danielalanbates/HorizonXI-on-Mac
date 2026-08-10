import SwiftUI
import AppKit

@main
struct HorizonXILauncherApp: App {
    var body: some Scene {
        WindowGroup("HorizonXI on Mac") {
            ContentView()
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Palette

private enum Sky {
    static let ink       = Color(red: 0.04, green: 0.05, blue: 0.10)
    static let deep      = Color(red: 0.07, green: 0.09, blue: 0.19)
    static let panel     = Color.white.opacity(0.06)
    static let stroke    = Color.white.opacity(0.12)
    static let gold      = Color(red: 0.85, green: 0.72, blue: 0.42)
    static let goldDim   = Color(red: 0.62, green: 0.52, blue: 0.30)
    static let text      = Color(red: 0.92, green: 0.93, blue: 0.97)
    static let muted     = Color(red: 0.62, green: 0.66, blue: 0.76)
}

struct ContentView: View {
    @State private var installs: [Install] = []
    @State private var selected: Install?
    @State private var checks: [Check] = []
    @State private var perf = PerfSettings.load()
    @StateObject private var runner = Runner()

    @StateObject private var store = ServerStore()
    @State private var newServer = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newProfile = ""

    @State private var user = Credentials.username
    @State private var pass = ""
    @State private var remember = Credentials.remember
    @State private var showDetails = false
    @State private var notice = ""

    private var blocked: Bool { checks.contains { $0.state == .bad } }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Sky.deep, Sky.ink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                hero
                Divider().overlay(Sky.stroke)
                sidebar.frame(width: 360)
            }
        }
        .onAppear {
            refresh()
            if remember, !user.isEmpty { pass = Credentials.password(for: user) }
        }
    }

    // MARK: - Left: hero + status

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text((store.selected?.name ?? "FINAL FANTASY XI").uppercased())
                    .font(.system(size: 46, weight: .light, design: .serif))
                    .tracking(10)
                    .foregroundStyle(Sky.text)
                Text("FINAL FANTASY XI ON APPLE SILICON")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Sky.goldDim)
                Text(store.selected?.note ?? "running natively — no virtual machine")
                    .font(.callout)
                    .foregroundStyle(Sky.muted)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 18)

            serverBar

            Spacer()

            if showDetails {
                ScrollView { statusList.padding(.horizontal, 32) }
                    .frame(maxHeight: 220)
            }

            logStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One button per server, HorizonXI first because it is the one that is actually verified.
    private var serverBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SERVER").font(.caption2).tracking(2).foregroundStyle(Sky.goldDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.servers) { s in
                        Button { store.select(s) } label: {
                            HStack(spacing: 6) {
                                Text(s.name).font(.system(size: 12, weight: .medium))
                                if !s.verified {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 9)).foregroundStyle(Sky.muted)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(s.name == store.selectedID ? Sky.gold.opacity(0.22)
                                                                 : Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(s.name == store.selectedID ? Sky.gold : Sky.stroke))
                            .foregroundStyle(s.name == store.selectedID ? Sky.gold : Sky.text)
                        }
                        .buttonStyle(.plain)
                        .help(s.verified ? s.host
                                         : "Untested here — set the login host before playing")
                        .contextMenu {
                            if !Server.builtins.contains(where: { $0.name == s.name }) {
                                Button("Remove \(s.name)") { store.remove(s) }
                            }
                        }
                    }
                    Button { newServer = true } label: {
                        Image(systemName: "plus")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Sky.stroke))
                            .foregroundStyle(Sky.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Add a server")
                }
            }
            if let s = store.selected, !s.verified {
                Text(s.host.isEmpty
                     ? "No login host set for \(s.name) — add it below before playing."
                     : "\(s.host) — untested by this project.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let s = store.selected, !s.verified {
                HStack(spacing: 6) {
                    TextField("login host", text: Binding(
                        get: { s.host },
                        set: { var c = s; c.host = $0; store.update(c) }))
                        .textFieldStyle(.roundedBorder).font(.caption)
                    TextField("boot profile .ini", text: Binding(
                        get: { s.bootProfile },
                        set: { var c = s; c.bootProfile = $0; store.update(c) }))
                        .textFieldStyle(.roundedBorder).font(.caption).frame(width: 150)
                }
            }
        }
        .padding(.horizontal, 32)
        .sheet(isPresented: $newServer) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a server").font(.headline)
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder)
                TextField("Login host", text: $newHost).textFieldStyle(.roundedBorder)
                TextField("Boot profile (.ini)", text: $newProfile).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { newServer = false }
                    Button("Add") {
                        store.add(name: newName, host: newHost, profile: newProfile)
                        newName = ""; newHost = ""; newProfile = ""; newServer = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 340)
        }
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(checks) { c in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(color(c.state)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.caption).foregroundStyle(Sky.text)
                        Text(c.detail).font(.caption2).foregroundStyle(Sky.muted)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var logStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Sky.stroke)
            ScrollViewReader { sp in
                ScrollView {
                    Text(runner.log.isEmpty ? "ready." : runner.log)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Sky.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .id("end")
                }
                .frame(height: 108)
                .onChange(of: runner.log) { _ in sp.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    // MARK: - Right: account + play

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ACCOUNT").font(.caption).tracking(2).foregroundStyle(Sky.goldDim)
                Spacer()
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).foregroundStyle(Sky.muted)
                    .help("Rescan for installs")
            }

            field("Account name", text: $user, secure: false)
            field("Password", text: $pass, secure: true)
            Toggle("Remember me", isOn: $remember)
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(Sky.muted)

            if installs.count > 1 {
                Picker("", selection: Binding(
                    get: { selected?.id ?? "" },
                    set: { id in selected = installs.first { $0.id == id }; recheck() })
                ) {
                    ForEach(installs) { i in
                        Text("\(i.wrapper.lastPathComponent) · \(i.prefixName)").tag(i.id)
                    }
                }
                .labelsHidden()
            }

            playButton

            if !notice.isEmpty {
                Text(notice).font(.caption2).foregroundStyle(Sky.gold)
            }

            Divider().overlay(Sky.stroke)

            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Fast synchronisation (msync)", isOn: $perf.msync)
                    Toggle("Silence wine debug channels", isOn: $perf.silenceWineDebug)
                    Toggle("Keep awake (no App Nap)", isOn: $perf.disableAppNap)
                    Toggle("Large address aware", isOn: $perf.largeAddressAware)
                    Toggle("Show frame rate (Metal HUD)", isOn: $perf.metalHUD)
                    HStack(spacing: 8) {
                        Button("Graphics…") { openFFXIConfig() }
                        Button("Repair") { if let i = selected { runner.repair(i) } }
                            .disabled(runner.busy)
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(Sky.muted)
                .padding(.top, 8)
                .onChange(of: perf.msync) { _ in perf.save() }
                .onChange(of: perf.silenceWineDebug) { _ in perf.save() }
                .onChange(of: perf.disableAppNap) { _ in perf.save() }
                .onChange(of: perf.largeAddressAware) { _ in perf.save() }
                .onChange(of: perf.metalHUD) { _ in perf.save() }
            } label: {
                Text("SETUP & GRAPHICS").font(.caption).tracking(2).foregroundStyle(Sky.goldDim)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle().fill(blocked ? .red : .green).frame(width: 6, height: 6)
                Text(blocked ? "setup incomplete" : "ready to play")
                    .font(.caption2).foregroundStyle(Sky.muted)
            }
        }
        .padding(22)
        .background(Sky.panel)
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2).tracking(1.5).foregroundStyle(Sky.muted)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .textFieldStyle(.plain)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Sky.stroke))
            .foregroundStyle(Sky.text)
        }
    }

    private var playButton: some View {
        Button(action: play) {
            Text(runner.running ? "RUNNING" : "PLAY")
                .font(.system(size: 15, weight: .semibold)).tracking(4)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(
                    LinearGradient(colors: runner.running ? [Sky.goldDim.opacity(0.4), Sky.goldDim.opacity(0.25)]
                                                          : [Sky.gold, Sky.goldDim],
                                   startPoint: .top, endPoint: .bottom))
                .foregroundStyle(Color.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(selected == nil || runner.running || blocked)
    }

    // MARK: - Actions

    private func play() {
        guard let i = selected else { return }
        notice = ""
        Credentials.username = user
        Credentials.remember = remember
        if remember { Credentials.savePassword(pass, for: user) }
        else { Credentials.deletePassword(for: user) }

        let server = store.selected ?? Server.builtins[0]
        guard !server.host.isEmpty else {
            notice = "\(server.name) has no login host set."
            return
        }
        if !user.isEmpty, !pass.isEmpty {
            if !Credentials.apply(user: user, password: pass, to: i,
                                  profile: server.bootProfile, server: server.host) {
                notice = "Could not write config/boot/\(server.bootProfile) — launching with its existing account."
            }
        }
        runner.launch(i, perf: perf, profile: server.bootProfile)
    }

    private func refresh() {
        installs = Install.discover()
        if selected == nil || !installs.contains(where: { $0.id == selected?.id }) {
            selected = installs.first
        }
        recheck()
    }

    private func recheck() { checks = selected.map { Preflight.run($0) } ?? [] }

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

    private func color(_ s: Check.State) -> Color {
        switch s {
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }
}
