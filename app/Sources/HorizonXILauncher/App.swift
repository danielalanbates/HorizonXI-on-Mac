import SwiftUI
import AppKit

@main
struct HorizonXILauncherApp: App {
    var body: some Scene {
        WindowGroup("FFXI on Mac") {
            ContentView()
                .frame(minWidth: 940, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Palette
//
// Vana'diel by way of the crystal: deep indigo night, crystal cyan, and the warm gold the game
// uses for every selected menu item. Deliberately not macOS-grey — this is a game launcher.

enum Vana {
    static let night     = Color(red: 0.05, green: 0.05, blue: 0.12)
    static let indigo    = Color(red: 0.11, green: 0.10, blue: 0.26)
    static let violet    = Color(red: 0.20, green: 0.14, blue: 0.36)
    static let crystal   = Color(red: 0.55, green: 0.83, blue: 0.95)
    static let crystalDim = Color(red: 0.33, green: 0.55, blue: 0.70)
    static let gold      = Color(red: 0.93, green: 0.79, blue: 0.44)
    static let goldDim   = Color(red: 0.66, green: 0.55, blue: 0.29)
    static let ember     = Color(red: 0.90, green: 0.45, blue: 0.35)
    static let panel     = Color(red: 0.08, green: 0.08, blue: 0.17).opacity(0.85)
    static let stroke    = Color.white.opacity(0.14)
    static let text      = Color(red: 0.94, green: 0.95, blue: 0.99)
    static let muted     = Color(red: 0.64, green: 0.68, blue: 0.80)

    /// The blue-violet wash behind everything, with a crystal glow up top.
    static var backdrop: some View {
        ZStack {
            LinearGradient(colors: [violet, indigo, night],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [crystal.opacity(0.22), .clear],
                           center: .init(x: 0.22, y: 0.08), startRadius: 8, endRadius: 460)
            RadialGradient(colors: [gold.opacity(0.10), .clear],
                           center: .init(x: 0.85, y: 0.95), startRadius: 8, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

struct ContentView: View {
    @State private var installs: [Install] = []
    @State private var selected: Install?
    @State private var checks: [Check] = []
    @State private var perf = PerfSettings.load()
    @StateObject private var runner = Runner()

    @StateObject private var store = ServerStore()
    @StateObject private var local = LocalServer()
    @State private var worldHover = false
    @State private var forceSetup = false
    @State private var newServer = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newProfile = ""

    @State private var user = Credentials.username
    @State private var pass = ""
    @State private var remember = Credentials.remember
    @State private var showDetails = false
    @State private var notice = ""
    @State private var scanning = false

    private var blocked: Bool { checks.contains { $0.state == .bad } }

    var body: some View {
        ZStack {
            Vana.backdrop
            HStack(spacing: 0) {
                hero
                Rectangle().fill(Vana.stroke).frame(width: 1)
                sidebar.frame(width: 372)
            }
        }
        .onAppear {
            if remember, !user.isEmpty { pass = Credentials.password(for: user) }
            if store.selected?.local == true { local.refresh() }
        }
        .onChange(of: store.selectedID) { _ in
            if store.selected?.local == true { local.refresh() }
        }
        // Discovery walks /Volumes, and an external drive can make that take tens of seconds.
        // Doing it on the main thread means the window never appears at all — which looked
        // exactly like the app failing to launch. Scan off the main actor and fill the UI in.
        .task { await refreshAsync() }
    }

    // MARK: - Left: title, server, status

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text((store.selected?.name ?? "FINAL FANTASY XI").uppercased())
                    .font(.system(size: 46, weight: .light, design: .serif))
                    .tracking(10)
                    .foregroundStyle(
                        LinearGradient(colors: [Vana.text, Vana.crystal],
                                       startPoint: .top, endPoint: .bottom))
                    .shadow(color: Vana.crystal.opacity(0.35), radius: 12, y: 2)
                Text("FINAL FANTASY XI ON APPLE SILICON")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3.5)
                    .foregroundStyle(Vana.gold)
                Text(store.selected?.note ?? "running natively — no virtual machine")
                    .font(.callout)
                    .foregroundStyle(Vana.muted)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 34).padding(.top, 34).padding(.bottom, 20)

            localServerCard
            rendererBanner
            notesCard
            Spacer()

            if showDetails {
                ScrollView { statusList.padding(.horizontal, 34) }
                    .frame(maxHeight: 200)
            }
            logStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One dropdown for every server, kept next to the account fields since choosing a world and
    /// typing the account that logs into it are one decision, not two. HorizonXI is pinned to the
    /// top; the rest are ordered by community size, which is metadata the user never has to see
    /// or maintain. Sized for the 372pt sidebar column rather than the wide hero pane.
    private var serverPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WORLD").font(.caption).tracking(2.5).foregroundStyle(Vana.gold)
                Spacer()
                if store.selected?.verified == true {
                    Label("verified", systemImage: "checkmark.seal.fill")
                        .labelStyle(.iconOnly).font(.caption2)
                        .foregroundStyle(Vana.crystal)
                        .help("This project logs into this server successfully.")
                } else {
                    Image(systemName: "questionmark.circle").font(.caption2)
                        .foregroundStyle(Vana.muted)
                        .help("Untested here — set the login host before playing.")
                }
            }

            Menu {
                ForEach(store.ordered) { s in
                    Button {
                        store.select(s)
                    } label: {
                        if s.era.isEmpty { Text(s.name) }
                        else { Text("\(s.name)  ·  \(s.era)") }
                    }
                }
                Divider()
                Button("Add a server…") { newServer = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Vana.crystal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.selected?.name ?? "Choose a world")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(Vana.text)
                            .lineLimit(1)
                        if let era = store.selected?.era, !era.isEmpty {
                            Text(era).font(.caption2).foregroundStyle(Vana.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    // A filled capsule reads as a control at a glance, the way a native pop-up
                    // button's chrome does; the plain chevron this replaced was easy to mistake
                    // for a static label instead of something to click.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(worldHover ? Vana.crystal : Vana.gold))
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(worldHover ? Color.white.opacity(0.10) : Color.black.opacity(0.32)))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(worldHover ? Vana.crystal : Vana.crystalDim.opacity(0.7),
                            lineWidth: worldHover ? 1.5 : 1))
                .contentShape(Rectangle())
                .onHover { hovering in
                    worldHover = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            if let s = store.selected, !s.verified {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("login host", text: Binding(
                        get: { s.host }, set: { var c = s; c.host = $0; store.update(c) }))
                        .textFieldStyle(.roundedBorder).font(.caption2)
                    HStack(spacing: 6) {
                        TextField("boot profile .ini", text: Binding(
                            get: { s.bootProfile }, set: { var c = s; c.bootProfile = $0; store.update(c) }))
                            .textFieldStyle(.roundedBorder).font(.caption2)
                        if !Server.builtins.contains(where: { $0.name == s.name }) {
                            Button(role: .destructive) { store.remove(s) } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                    Text(s.host.isEmpty
                         ? "No login host set for \(s.name) — add it before playing."
                         : "\(s.host) — untested by this project.")
                        .font(.caption2).foregroundStyle(Vana.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $newServer) { addServerSheet }
    }

    private var addServerSheet: some View {
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
        .padding(20).frame(width: 360)
    }

    /// Shown only for the local world. Selecting it means building an FFXI server on this Mac, so
    /// this says what that will cost and what is left to do before Play can work.
    @ViewBuilder private var localServerCard: some View {
        if store.selected?.local == true {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Your own server", systemImage: "internaldrive")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Vana.gold)
                    Spacer()
                    if local.busy {
                        ProgressView().controlSize(.small)
                        Text(local.activity).font(.caption2).foregroundStyle(Vana.muted)
                    }
                }

                if let s = local.status {
                    // Disk first: it is the one thing the user has to fix outside this app, and
                    // finding out 20 minutes into a build is far worse than finding out here.
                    // Once the server is built the space warning is about the *next* build, not
                    // this one, so state the number without dressing it as a problem.
                    HStack(spacing: 6) {
                        Image(systemName: (s.spaceOK || s.ready)
                              ? "checkmark.circle" : "exclamationmark.triangle.fill")
                            .foregroundStyle((s.spaceOK || s.ready) ? Vana.crystal : Vana.ember)
                        Text(s.ready
                             ? String(format: "%.1f GB free on this disk", s.freeGB)
                             : String(format: "%.1f GB free · about %.0f GB needed",
                                      s.freeGB, s.needGB))
                            .font(.caption)
                            .foregroundStyle((s.spaceOK || s.ready) ? Vana.text : Vana.ember)
                    }

                    if !s.spaceOK && !s.ready {
                        Text(s.belowFloor
                             ? "Not enough room to install a server. It needs roughly \(Int(s.needGB)) GB — "
                               + "about 5 GB of source, 3 GB of build output, and headroom for the "
                               + "database and the compiler. Free up space, then set up."
                             : "Below the recommended \(Int(s.needGB)) GB but above the "
                               + "\(Int(s.floorGB)) GB minimum. Setup will run, and may run tight.")
                            .font(.caption2).foregroundStyle(Vana.ember)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if s.ready {
                        row("Server", s.running
                            ? "running · \(s.up.count) of 4 processes"
                            : "built and ready — Play will start it")
                    } else {
                        row("Still to do", s.todo)
                        Text("Setting up downloads Homebrew packages and the LandSandBoat source, "
                             + "imports the game database and compiles the server. Budget half an "
                             + "hour or more the first time; it can be re-run if it stops.")
                            .font(.caption2).foregroundStyle(Vana.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    row("Location", s.root)

                    HStack(spacing: 8) {
                        if !s.ready {
                            Button(s.source ? "Continue setup" : "Set up server") {
                                local.setup(force: s.belowFloor && forceSetup,
                                            log: { runner.appendLine($0) })
                            }
                            .disabled(local.busy || (s.belowFloor && !forceSetup))
                            if s.belowFloor {
                                Toggle("Set up anyway", isOn: $forceSetup)
                                    .toggleStyle(.checkbox).font(.caption2)
                                    .foregroundStyle(Vana.muted)
                            }
                        }
                        if s.ready {
                            Button(s.running ? "Stop server" : "Start server") {
                                if s.running { local.stop(log: { runner.appendLine($0) }) }
                                else { local.start(log: { runner.appendLine($0) }) }
                            }
                            .disabled(local.busy)
                        }
                        Button("Refresh") { local.refresh() }.disabled(local.busy)
                    }
                    .padding(.top, 2)
                } else {
                    Text("checking what is installed…")
                        .font(.caption2).foregroundStyle(Vana.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: 500, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Vana.stroke))
            .padding(.horizontal, 34).padding(.top, 14)
        }
    }

    /// Say plainly when the chosen renderer is not one you can actually play on.
    @ViewBuilder private var rendererBanner: some View {
        if !perf.renderer.playable {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Vana.ember)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(perf.renderer.title) is experimental")
                        .font(.caption).foregroundStyle(Vana.text)
                    Text(perf.renderer.blurb).font(.caption2).foregroundStyle(Vana.muted)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Vana.ember.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Vana.ember.opacity(0.35)))
            .padding(.horizontal, 34).padding(.top, 14)
            .frame(maxWidth: 500, alignment: .leading)
        }
    }

    /// The Horizon launcher fills this space with news. This project's equivalent is honest
    /// status: what the current renderer does, and where the write-up lives.
    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Vana'diel on Apple Silicon", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(Vana.gold)

            row("Renderer", perf.renderer.title)
            row("Wine prefix", selected?.prefixName ?? (scanning ? "scanning…" : "not found"))
            row("Client", selected == nil ? (scanning ? "scanning…" : "not found") : "Ashita · \(store.selected?.bootProfile ?? "")")

            Text("Measured on this Mac with Metal/DXVK: rendering is correct, fog included. "
                 + "About 24 fps in the menus and 7.5 fps in the world. The limit is not the "
                 + "renderer — see docs/PERFORMANCE.md.")
                .font(.caption2).foregroundStyle(Vana.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: 500, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Vana.stroke))
        .padding(.horizontal, 34).padding(.top, 16)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k.uppercased()).font(.system(size: 9)).tracking(1.2)
                .foregroundStyle(Vana.crystalDim).frame(width: 84, alignment: .leading)
            Text(v).font(.caption).foregroundStyle(Vana.text)
            Spacer()
        }
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(checks) { c in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(color(c.state)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.caption).foregroundStyle(Vana.text)
                        Text(c.detail).font(.caption2).foregroundStyle(Vana.muted)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var logStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Vana.stroke).frame(height: 1)
            ScrollViewReader { sp in
                ScrollView {
                    Text(runner.log.isEmpty ? "ready." : runner.log)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Vana.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .id("end")
                }
                .frame(height: 108)
                .onChange(of: runner.log) { _ in sp.scrollTo("end", anchor: .bottom) }
            }
        }
        .background(Color.black.opacity(0.28))
    }

    // MARK: - Right: account + play

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            serverPicker

            Rectangle().fill(Vana.stroke).frame(height: 1)

            HStack {
                Text("ACCOUNT").font(.caption).tracking(2.5).foregroundStyle(Vana.gold)
                Spacer()
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).foregroundStyle(Vana.muted)
                    .help("Rescan for installs")
            }

            field("Account name", text: $user, secure: false)
            field("Password", text: $pass, secure: true)
            Toggle("Remember me", isOn: $remember)
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(Vana.muted)
                .help("Stored in the macOS Keychain, never in a file in this project.")

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
                Text(notice).font(.caption2).foregroundStyle(Vana.gold)
            }

            Rectangle().fill(Vana.stroke).frame(height: 1)

            rendererSection

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
                .foregroundStyle(Vana.muted)
                .padding(.top, 8)
                .onChange(of: perf.msync) { _ in perf.save() }
                .onChange(of: perf.silenceWineDebug) { _ in perf.save() }
                .onChange(of: perf.disableAppNap) { _ in perf.save() }
                .onChange(of: perf.largeAddressAware) { _ in perf.save() }
                .onChange(of: perf.metalHUD) { _ in perf.save() }
            } label: {
                Text("SETUP & DIAGNOSTICS").font(.caption).tracking(2.5)
                    .foregroundStyle(Vana.gold)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle().fill(scanning ? Vana.gold : (blocked ? Vana.ember : Vana.crystal)).frame(width: 6, height: 6)
                Text(scanning ? "looking for your install…" : (blocked ? "setup incomplete" : "ready to play"))
                    .font(.caption2).foregroundStyle(Vana.muted)
            }
        }
        .padding(22)
        .background(Vana.panel)
    }

    private var rendererSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RENDERER").font(.caption).tracking(2.5).foregroundStyle(Vana.gold)
            Picker("", selection: $perf.renderer) {
                ForEach(Renderer.allCases) { r in Text(r.title).tag(r) }
            }
            .labelsHidden()
            .onChange(of: perf.renderer) { _ in perf.save() }
            Text(perf.renderer.blurb)
                .font(.caption2).foregroundStyle(Vana.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2).tracking(1.5).foregroundStyle(Vana.muted)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .textFieldStyle(.plain)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.40)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Vana.crystalDim.opacity(0.5)))
            .foregroundStyle(Vana.text)
        }
    }

    private var playButton: some View {
        Button(action: play) {
            Text(runner.running ? "RUNNING" : "PLAY")
                .font(.system(size: 15, weight: .semibold, design: .serif)).tracking(5)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(
                    LinearGradient(colors: runner.running
                                   ? [Vana.goldDim.opacity(0.45), Vana.goldDim.opacity(0.25)]
                                   : [Vana.gold, Vana.goldDim],
                                   startPoint: .top, endPoint: .bottom))
                .foregroundStyle(Color.black.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Vana.gold.opacity(runner.running ? 0 : 0.35), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        // Only the *absence* of an install should block Play. Once we have one — remembered
        // or found — a still-running background rescan must not hold the user up.
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

        // The local world has to be running before the client can reach it. Start it here rather
        // than making the user press two buttons in the right order — but never build from Play,
        // because a first build is a half-hour job the user should be choosing deliberately.
        if server.local {
            guard let s = local.status, s.ready else {
                notice = local.status == nil
                    ? "Still checking the local server."
                    : "The local server is not set up yet — press “Set up server”."
                return
            }
            if !s.running {
                local.start(log: { runner.appendLine($0) }) { ok in
                    if ok { launchClient(i, server: server) }
                    else { notice = "The local server did not start — see the log." }
                }
                return
            }
        }
        launchClient(i, server: server)
    }

    private func launchClient(_ i: Install, server: Server) {
        // A world the install has no boot profile for — the local one, on every machine — needs
        // that file to exist before anything can be written into it.
        if !Credentials.ensureProfile(server.bootProfile, in: i) {
            notice = "Could not create config/boot/\(server.bootProfile)."
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

    private func refresh() { Task { await refreshAsync() } }

    private func refreshAsync() async {
        // Use the install we used last time straight away. Scanning /Volumes can take a long
        // time on a slow external drive — long enough that the launcher never became usable —
        // and there is no reason to make the user wait for a path we already know.
        if selected == nil, let remembered = Install.remembered() {
            selected = remembered
            installs = [remembered]
            await recheckAsync()
        }

        scanning = true
        let found = await Task.detached(priority: .userInitiated) { Install.discover() }.value
        scanning = false
        guard !found.isEmpty else { return }
        installs = found
        if selected == nil || !found.contains(where: { $0.id == selected?.id }) {
            selected = found.first
        }
        selected?.remember()
        await recheckAsync()
    }

    private func recheck() { Task { await recheckAsync() } }

    private func recheckAsync() async {
        guard let i = selected else { checks = []; return }
        checks = await Task.detached(priority: .userInitiated) { Preflight.run(i) }.value
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

    private func color(_ s: Check.State) -> Color {
        switch s {
        case .ok: return Vana.crystal
        case .warn: return Vana.gold
        case .bad: return Vana.ember
        }
    }
}
