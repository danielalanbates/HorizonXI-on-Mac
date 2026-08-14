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
    @StateObject private var feeds = ServerFeeds()
    @State private var bannerIndex = 0
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
    @State private var showGraphics = false
    @State private var graphics = GraphicsSettings.load()
    @State private var showAddons = false
    @State private var addonItems: [AddonSuite.Item] = []
    @State private var addonWarning = ""
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
            if store.selected?.local == true { local.refresh() }
            // Off the main actor out of habit from when this was a Keychain read that could
            // block on a system prompt (see Credentials.swift for why it no longer is).
            guard remember, !user.isEmpty else { return }
            let account = user
            let install = selected
            let profile = store.selected?.bootProfile ?? "horizonxi.ini"
            Task.detached(priority: .userInitiated) {
                if let i = install {
                    Credentials.adoptPasswordFromProfile(user: account, install: i, profile: profile)
                }
                let found = Credentials.password(for: account)
                await MainActor.run { pass = found }
            }
        }
        .onChange(of: store.selectedID) { _ in
            if store.selected?.local == true { local.refresh() }
        }
        // Discovery walks /Volumes, and an external drive can make that take tens of seconds.
        // Doing it on the main thread means the window never appears at all — which looked
        // exactly like the app failing to launch. Scan off the main actor and fill the UI in.
        .task {
            await refreshAsync()
            // Pick up each server's own published addon list, so the app's compiled-in snapshot
            // does not go stale between releases. Silent on failure -- offline must still launch.
            await feeds.refreshAsync(servers: store.servers)
        }
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
                newsBanner
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
        .sheet(isPresented: $showGraphics) { graphicsSheet }
        .sheet(isPresented: $showAddons) { addonsSheet }
    }

    /// What the selected server permits. See `AddonPolicy` for why an unsourced policy shows
    /// everything rather than guessing at a list. A list fetched from the server's own page this
    /// launch beats the snapshot compiled into the app.
    private var addonPolicy: AddonPolicy {
        guard let s = store.selected else { return .unknown }
        return AddonPolicies.policy(for: s, fetched: feeds.fetchedAddonLists)
    }

    /// A rotating strip of what the launcher knows about the selected world.
    ///
    /// Every line here is something the launcher actually holds -- the server's era, its own
    /// note, the state of its addon rules, whether this project has tested it. **Nothing is
    /// invented to fill the space.** No FFXI private server publishes a news feed a launcher can
    /// read (see `ServerFeeds` for what was checked), so there are no headlines to rotate; the
    /// moment one does, fetched items appear here first and are marked as such.
    @ViewBuilder
    private var newsBanner: some View {
        let items = feeds.bannerItems(for: store.selected, policy: addonPolicy)
        if items.isEmpty {
            Text("running natively — no virtual machine")
                .font(.callout).foregroundStyle(Vana.muted).padding(.top, 4)
        } else {
            let item = items[min(bannerIndex, items.count - 1) % items.count]
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(item.fetched ? Vana.gold : Vana.crystal.opacity(0.5))
                    .frame(width: 6, height: 6).padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.callout).foregroundStyle(Vana.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = item.url {
                        Link("Open \(url.host ?? "page")", destination: url)
                            .font(.caption2).foregroundStyle(Vana.gold)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 46, alignment: .top)
            .padding(.top, 4)
            .id(item.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.45), value: bannerIndex)
            .onReceive(Timer.publish(every: 7, on: .main, in: .common).autoconnect()) { _ in
                bannerIndex = (bannerIndex + 1) % max(items.count, 1)
            }
        }
    }

    // Built outside the view body: as interpolated expressions inline, the type-checker gave up
    // on them ("unable to type-check this expression in reasonable time").
    private static func unknownPolicyNote(_ server: String) -> String {
        "This server's addon rules are not published anywhere this launcher could source them, "
        + "so nothing below is filtered. Check what \(server) allows before you use it — on most "
        + "private servers an unapproved addon is a bannable offence."
    }

    private static func allowlistNote(_ server: String, hidden: Int, source: String) -> String {
        var s = "Showing only what \(server) approves"
        if hidden > 0 {
            let noun = hidden == 1 ? "item is" : "items are"
            s += " — \(hidden) installed \(noun) hidden because they are not on the list"
        }
        return s + ". Source: \(source)."
    }

    @ViewBuilder
    private var addonPolicyNote: some View {
        let policy = addonPolicy
        let serverName = store.selected?.name ?? "this server"
        let hidden = addonItems.filter { !policy.allows($0.name) }.count
        switch policy {
        case .unknown:
            Text(Self.unknownPolicyNote(serverName))
                .font(.caption2).foregroundStyle(Vana.ember)
                .fixedSize(horizontal: false, vertical: true)
        case let .unrestricted(reason):
            Text(reason).font(.caption2).foregroundStyle(Vana.muted)
                .fixedSize(horizontal: false, vertical: true)
        case let .allowlist(_, source):
            Text(Self.allowlistNote(serverName, hidden: hidden, source: source))
                .font(.caption2).foregroundStyle(Vana.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ashita's plugins and Lua addons, the same set HorizonXI's own launcher manages.
    private var addonsSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Addons & plugins").font(.headline)
            Text("Written to scripts/default.txt, between the launcher-managed markers. Anything "
                 + "you added by hand outside those blocks is left alone.")
                .font(.caption).foregroundStyle(Vana.muted)

            addonPolicyNote

            if !addonWarning.isEmpty {
                Text(addonWarning).font(.caption2).foregroundStyle(Vana.ember)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List {
                Section("Plugins") {
                    ForEach($addonItems.filter {
                        $0.wrappedValue.isPlugin && addonPolicy.allows($0.wrappedValue.name)
                    }) { $item in
                        Toggle(item.name, isOn: $item.enabled)
                    }
                }
                Section("Addons") {
                    ForEach($addonItems.filter {
                        !$0.wrappedValue.isPlugin && addonPolicy.allows($0.wrappedValue.name)
                    }) { $item in
                        Toggle(item.name, isOn: $item.enabled)
                    }
                }
            }
            .frame(height: 320)

            HStack {
                // "All" means all the ones this server permits. Enabling something the server
                // forbids is not a convenience, it is a ban.
                Button("Enable all") {
                    for i in addonItems.indices where addonPolicy.allows(addonItems[i].name) {
                        addonItems[i].enabled = true
                    }
                }
                Button("Disable all") {
                    for i in addonItems.indices { addonItems[i].enabled = false }
                }
                Spacer()
                Button("Cancel") { showAddons = false }
                Button("Apply") {
                    // Belt and braces: a hidden row cannot be toggled on, but the list on disk
                    // may already have named something this server forbids, and pressing Apply
                    // must not write it back out.
                    for i in addonItems.indices where !addonPolicy.allows(addonItems[i].name) {
                        addonItems[i].enabled = false
                    }
                    if let i = selected, !AddonSuite.write(addonItems, to: i) {
                        notice = "Could not write scripts/default.txt — its launcher markers are missing."
                    } else {
                        notice = "Addon list saved. It takes effect the next time you press Play."
                    }
                    showAddons = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 460)
    }

    /// FFXI's own graphics settings, written into the selected world's boot profile. See
    /// `GraphicsSettings` for why this is not a wrapper around Config.exe.
    private var graphicsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Graphics").font(.headline)
            Text("Applied to \(store.selected?.bootProfile ?? "the boot profile") the next time "
                 + "you press Play.")
                .font(.caption).foregroundStyle(Vana.muted)

            Picker("Resolution", selection: Binding(
                get: { "\(graphics.width)x\(graphics.height)" },
                set: { id in
                    let parts = id.split(separator: "x").compactMap { Int($0) }
                    if parts.count == 2 { graphics.width = parts[0]; graphics.height = parts[1] }
                })) {
                ForEach(GraphicsSettings.resolutions, id: \.0) { r in
                    Text(r.0).tag("\(r.1)x\(r.2)")
                }
            }
            Picker("Texture resolution", selection: $graphics.textureResolution) {
                ForEach([512, 1024, 2048, 4096], id: \.self) { Text(String($0)).tag($0) }
            }
            Picker("Mip mapping", selection: $graphics.mipMapping) {
                ForEach(0...4, id: \.self) { Text($0 == 0 ? "Off" : String($0)).tag($0) }
            }
            Picker("Textures", selection: $graphics.textureCompression) {
                Text("Uncompressed").tag(0)
                Text("Compressed").tag(2)
            }
            Toggle("Bump mapping", isOn: $graphics.bumpMapping)
            Toggle("Environmental animation", isOn: $graphics.environmentAnimation)
            Divider()
            Toggle("Match interface to render resolution", isOn: $graphics.uiFollowsResolution)
            if !graphics.uiFollowsResolution {
                Picker("Interface resolution", selection: Binding(
                    get: { "\(graphics.uiWidth)x\(graphics.uiHeight)" },
                    set: { id in
                        let parts = id.split(separator: "x").compactMap { Int($0) }
                        if parts.count == 2 { graphics.uiWidth = parts[0]; graphics.uiHeight = parts[1] }
                    })) {
                    ForEach(GraphicsSettings.uiResolutions, id: \.0) { r in
                        Text(r.0).tag("\(r.1)x\(r.2)")
                    }
                }
                Text("FFXI draws the interface at this resolution and scales it up to the "
                     + "window, so a lower number means bigger menus and text. The world is "
                     + "still drawn at the render resolution above.")
                    .font(.caption2).foregroundStyle(Vana.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Balanced") { graphics = .balanced }
                Button("Max (4K)") { graphics = .max4K }
                Spacer()
                Button("Cancel") { showGraphics = false }
                Button("Apply") {
                    graphics.save()
                    if let i = selected, let s = store.selected {
                        Credentials.ensureProfile(s.bootProfile, in: i)
                        graphics.write(to: i, profile: s.bootProfile)
                        notice = "Graphics written to \(s.bootProfile)."
                    }
                    showGraphics = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20).frame(width: 380)
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

            Text("Measured on this Mac with Metal/DXVK: rendering is correct, fog included, "
                 + "at 4K with every setting at maximum — see docs/MAX4K.md.")
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
                Button { chooseInstall() } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).foregroundStyle(Vana.muted)
                    .help("Choose install… — point at the wrapper app if it lives somewhere the "
                          + "scan does not look, such as Downloads")
            }

            // The local server auto-creates its own account on first login (see LocalServer.swift)
            // -- there is no real account to type here, so the fields are disabled rather than
            // left editable and silently ignored.
            field("Account name", text: $user, secure: false, disabled: store.selected?.local == true)
            field("Password", text: $pass, secure: true, disabled: store.selected?.local == true)
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

            // Graphics and addons are things people change often -- they belong next to Play,
            // not inside a collapsed diagnostics section.
            HStack(spacing: 8) {
                Button("Graphics…") { openGraphics() }
                Button("Addons…") { openAddons() }
            }
            .font(.caption)

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
                    Toggle("Fast lens flares (skip occlusion wait) — glitches", isOn: $perf.flareReadbackNoWait)
                        .help("Roughly doubles the frame rate: FFXI stops the whole frame four "
                              + "times to read back a 16×16 visibility test. But it hands the game "
                              + "a buffer the GPU has not finished writing, so NPCs blink in and "
                              + "out about once a second. Off until that is fixed properly.")
                    Toggle("Show frame rate (Metal HUD)", isOn: $perf.metalHUD)
                    HStack(spacing: 8) {
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

    private func field(_ title: String, text: Binding<String>, secure: Bool,
                       disabled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2).tracking(1.5).foregroundStyle(Vana.muted)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .textFieldStyle(.plain)
            .disabled(disabled)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.40)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Vana.crystalDim.opacity(0.5)))
            .foregroundStyle(disabled ? Vana.muted : Vana.text)
            .opacity(disabled ? 0.5 : 1)
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
        // Two servers on the list publish no login host anywhere this project could find. Ashita
        // would take `--server ` with nothing after it and fail somewhere less obvious, so say
        // what is actually missing instead.
        if server.host.trimmingCharacters(in: .whitespaces).isEmpty {
            notice = "\(server.name) has no login host set. Get it from that server's own "
                   + "launcher or setup guide and put it in the server's Host field."
            return
        }
        // A world the install has no boot profile for — the local one, on every machine — needs
        // that file to exist before anything can be written into it.
        if !Credentials.ensureProfile(server.bootProfile, in: i) {
            notice = "Could not create config/boot/\(server.bootProfile)."
            return
        }
        // The client was installed by HorizonXI and carries their logo in its own data. On any
        // other world, show the stock title screen instead. See Branding.swift.
        Branding.apply(stockBranding: Branding.wantsStockBranding(server), to: i)

        if !user.isEmpty, !pass.isEmpty {
            if !Credentials.apply(user: user, password: pass, to: i,
                                  profile: server.bootProfile, server: server.host) {
                notice = "Could not write config/boot/\(server.bootProfile) — launching with its existing account."
            }
        }
        runner.launch(i, perf: perf, profile: server.bootProfile)
    }

    private func refresh() { Task { await refreshAsync() } }

    /// Point the launcher at a wrapper the scan cannot reach. Choosing it through a panel is
    /// also what grants access to a TCC-gated location such as Downloads, so this is the whole
    /// reason the scan itself does not need to go there.
    private func chooseInstall() {
        let panel = NSOpenPanel()
        panel.title = "Choose your HorizonXI wrapper"
        panel.message = "Pick the wrapper app that contains the game — usually siku.app."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let found = Install.installs(inWrapper: url)
        guard !found.isEmpty else {
            notice = "No HorizonXI install inside \(url.lastPathComponent)."
            return
        }
        for i in found where !installs.contains(where: { $0.id == i.id }) { installs.append(i) }
        selected = found.first
        selected?.remember()
        recheck()
    }

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

    /// Open the panel on whatever the profile actually says, not on this app's last write —
    /// the boot .ini is a plain text file the user may well have edited by hand.
    private func openGraphics() {
        if let i = selected, let s = store.selected,
           let onDisk = GraphicsSettings.read(from: i, profile: s.bootProfile) {
            graphics = onDisk
        }
        showGraphics = true
    }

    private func openAddons() {
        guard let i = selected else { return }
        addonItems = AddonSuite.scan(i)
        let bad = AddonSuite.mismatchedPlugins(i)
        addonWarning = bad.isEmpty ? "" :
            "Ashita refused these plugins on the last run because they are built for a different "
            + "interface version than this Ashita core: \(bad.joined(separator: ", ")). "
            + (bad.contains { $0.lowercased() == "addons" }
               ? "That includes the Lua host, so no addon below can run until it is fixed."
               : "")
        showAddons = true
    }

    private func color(_ s: Check.State) -> Color {
        switch s {
        case .ok: return Vana.crystal
        case .warn: return Vana.gold
        case .bad: return Vana.ember
        }
    }
}
