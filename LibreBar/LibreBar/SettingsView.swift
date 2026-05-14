import SwiftUI
import ServiceManagement

// MARK: - Connect State Machine

enum ConnectState {
    case idle, connecting, connected
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var glucose: GlucoseManager
    @State private var email = ""
    @State private var password = ""
    @State private var region = "us"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var connectState: ConnectState = .idle

    private let regions = [
        ("us", "United States"),
        ("eu", "Europe"),
        ("de", "Germany"),
        ("fr", "France"),
        ("au", "Australia"),
        ("ca", "Canada"),
        ("ap", "Asia Pacific"),
        ("jp", "Japan")
    ]

    var body: some View {
        VStack(spacing: 0) {
            heroHeader

            // Two-column body
            HStack(alignment: .top, spacing: 14) {
                // Left column
                VStack(spacing: 14) {
                    connectionSection
                    generalSection
                }
                .frame(maxWidth: .infinity)

                // Right column
                VStack(spacing: 14) {
                    displaySection
                    targetRangeSection
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 14)

            versionFooter
                .padding(.bottom, 14)
        }
        .frame(width: 930)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            email = glucose.email
            region = glucose.region
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.37, green: 0.61, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.blue.opacity(0.3), radius: 7, y: 3)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("LibreBar")
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.3)
                Text("Continuous glucose, right in the menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            statusPill
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(
            RadialGradient(
                colors: [Color.blue.opacity(0.08), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 300
            )
        )
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(pillDotColor)
                    .frame(width: 7, height: 7)

                if pillShowsPulse {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: connectState
                        )
                }
            }

            Text(pillLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.14), in: Capsule())
    }

    private var pillDotColor: Color {
        if connectState == .connecting { return .orange }
        if connectState == .connected { return .green }
        if glucose.latestReading != nil { return .green }
        if glucose.errorMessage != nil { return .red }
        return Color.gray.opacity(0.55)
    }

    private var pillLabel: String {
        if connectState == .connecting { return "Connecting..." }
        if connectState == .connected { return "Connected" }
        if glucose.latestReading != nil { return "Connected" }
        if glucose.errorMessage != nil { return "Error" }
        return glucose.isNightscout ? "Nightscout" : "LibreLinkUp"
    }

    private var pillShowsPulse: Bool {
        connectState == .connecting
    }

    private var pulseScale: CGFloat {
        connectState == .connecting ? 2.4 : 1.0
    }

    private var pulseOpacity: Double {
        connectState == .connecting ? 0.0 : 0.75
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        SettingsSection(label: "CONNECTION") {
            GroupedCard {
                VStack(spacing: 0) {
                    SettingsRow(label: "Data Source") {
                        Picker("", selection: $glucose.dataSource) {
                            Text("LibreLinkUp").tag("libre")
                            Text("Nightscout").tag("nightscout")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: glucose.dataSource) { _, _ in
                            glucose.clearData()
                            Task { await glucose.fetchGlucose() }
                        }
                    }

                    if glucose.isNightscout {
                        SettingsRow(label: "URL") {
                            TextField("https://your-site.herokuapp.com", text: $glucose.nightscoutURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        SettingsRow(label: "Token", hint: "Optional") {
                            SecureField("Access token", text: $glucose.nightscoutToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }
                    } else {
                        SettingsRow(label: "Email") {
                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        SettingsRow(label: "Password") {
                            SecureField("Required", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        SettingsRow(label: "Region") {
                            Picker("", selection: $region) {
                                ForEach(regions, id: \.0) { r in
                                    Text(r.1).tag(r.0)
                                }
                            }
                            .labelsHidden()
                        }

                        if glucose.connections.count > 1 {
                            SettingsRow(label: "Monitor") {
                                Picker("", selection: $glucose.selectedConnectionId) {
                                    ForEach(glucose.connections) { conn in
                                        Text(conn.displayName).tag(conn.id)
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: glucose.selectedConnectionId) { _, _ in
                                    Task { await glucose.fetchGlucose() }
                                }
                            }
                        }
                    }

                    connectFooter
                }
            }
        }
    }

    private var connectFooter: some View {
        HStack {
            if let error = glucose.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 11))
                    .lineLimit(2)
            }
            Spacer()
            connectButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.015)], startPoint: .top, endPoint: .bottom)
        )
    }

    private var connectButton: some View {
        Button(action: performConnect) {
            HStack(spacing: 7) {
                switch connectState {
                case .idle:
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text("Save & Connect")
                case .connecting:
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Connecting...")
                case .connected:
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Connected")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(minWidth: 148, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(connectState == .connected ? Color.green : Color.accentColor)
                    .shadow(color: .white.opacity(0.2), radius: 0, y: -1)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isConnectDisabled)
        .opacity(isConnectDisabled && connectState == .idle ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.26), value: connectState)
    }

    private var isConnectDisabled: Bool {
        if connectState != .idle { return true }
        return glucose.isNightscout ? glucose.nightscoutURL.isEmpty : (email.isEmpty || password.isEmpty)
    }

    private func performConnect() {
        guard connectState == .idle else { return }

        withAnimation(.easeInOut(duration: 0.26)) {
            connectState = .connecting
        }

        if glucose.isNightscout {
            Task {
                await glucose.fetchGlucose()
                withAnimation(.easeInOut(duration: 0.26)) {
                    connectState = .connected
                }
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                withAnimation(.easeInOut(duration: 0.26)) {
                    connectState = .idle
                }
            }
        } else {
            glucose.configure(email: email, password: password, region: region)
            Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                withAnimation(.easeInOut(duration: 0.26)) {
                    connectState = .connected
                }
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                withAnimation(.easeInOut(duration: 0.26)) {
                    connectState = .idle
                }
            }
        }
    }

    // MARK: - Display Section

    private var displaySection: some View {
        SettingsSection(label: "DISPLAY") {
            GroupedCard {
                VStack(spacing: 0) {
                    SettingsRow(label: "Units") {
                        Picker("", selection: $glucose.useMgdl) {
                            Text("mmol/L").tag(false)
                            Text("mg/dL").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    SettingsRow(label: "Menu Bar", hint: "Always shown") {
                        HStack(spacing: 14) {
                            checkboxToggle("Color dot", isOn: $glucose.showColorDot)
                            checkboxToggle("Sparkline", isOn: $glucose.showSparkline)
                        }
                    }

                    SettingsRow(label: "Graph") {
                        HStack(spacing: 14) {
                            checkboxToggle("Min/Max", isOn: $glucose.showMinMax)
                            checkboxToggle("Prediction", isOn: $glucose.showPredictionLine)
                        }
                    }

                }
            }
        }
    }

    private func checkboxToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
    }

    // MARK: - Target Range Section

    private var targetRangeSection: some View {
        SettingsSection(label: "TARGET RANGE", hint: glucose.useMgdl ? "mg/dL" : "mmol/L") {
            GroupedCard {
                VStack(spacing: 0) {
                    // Range visualizer
                    RangeVisualizerBar(
                        low: glucose.lowThreshold,
                        high: glucose.highThreshold,
                        useMgdl: glucose.useMgdl
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 30)
                    .padding(.bottom, 14)

                    rangeSliderRow(
                        label: "Low",
                        color: .orange,
                        value: $glucose.lowThreshold,
                        range: 2.5...(glucose.highThreshold - 0.2),
                        step: 0.1
                    )

                    rangeSliderRow(
                        label: "High",
                        color: .red,
                        value: $glucose.highThreshold,
                        range: (glucose.lowThreshold + 0.2)...16.0,
                        step: 0.1
                    )
                }
            }
        }
    }

    private func formatRangeValue(_ value: Double) -> String {
        glucose.useMgdl ? "\(Int(round(value * 18.0182)))" : String(format: "%.1f", value)
    }

    private func rangeSliderRow(label: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 13))
            }
            .frame(width: 50, alignment: .leading)

            Slider(value: value, in: range, step: step)

            Text(formatRangeValue(value.wrappedValue))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - General Section

    private var generalSection: some View {
        SettingsSection(label: "GENERAL") {
            GroupedCard {
                VStack(spacing: 0) {
                    SettingsRow(label: "Launch at Login") {
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(.green)
                            .onChange(of: launchAtLogin) { _, newValue in
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    print("[LibreBar] Launch at login error: \(error)")
                                    launchAtLogin = !newValue
                                }
                            }
                    }

                    SettingsRow(label: "Shortcut", hint: "Toggle popover") {
                        ShortcutKeycaps()
                    }

                    SettingsRow(label: "Updates") {
                        Button(action: {
                            UpdateChecker.shared.checkForUpdates(silent: false)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "icloud.and.arrow.down")
                                    .font(.system(size: 11))
                                Text("Check for Updates")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.04), radius: 0, y: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        HStack(spacing: 6) {
            Text("LibreBar v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
            Text("·")
                .opacity(0.6)
            Text("Open source on GitHub")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Range Visualizer (Canvas-based)

struct RangeVisualizerBar: View {
    let low: Double
    let high: Double
    let useMgdl: Bool

    private let rangeMin: Double = 2.5
    private let rangeMax: Double = 16.0

    private var span: Double { rangeMax - rangeMin }
    private var lowFrac: CGFloat { CGFloat((low - rangeMin) / span) }
    private var highFrac: CGFloat { CGFloat((high - rangeMin) / span) }

    private func fmtValue(_ v: Double) -> String {
        useMgdl ? "\(Int(round(v * 18.0182)))" : String(format: "%.1f", v)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let barH: CGFloat = 10
            let barY: CGFloat = geo.size.height - barH

            Canvas { ctx, size in
                let barRect = CGRect(x: 0, y: barY, width: w, height: barH)

                // Background track
                let bgPath = Path(roundedRect: barRect, cornerRadius: 5)
                ctx.fill(bgPath, with: .color(Color.gray.opacity(0.1)))

                // Low zone (orange)
                let lowW = w * lowFrac
                if lowW > 0 {
                    let lowRect = CGRect(x: 0, y: barY, width: lowW, height: barH)
                    let lowPath = Path(roundedRect: lowRect, cornerRadii: .init(topLeading: 5, bottomLeading: 5, bottomTrailing: 0, topTrailing: 0))
                    ctx.fill(lowPath, with: .color(Color.orange.opacity(0.32)))
                }

                // OK zone (green)
                let okX = w * lowFrac
                let okW = w * (highFrac - lowFrac)
                if okW > 0 {
                    let okRect = CGRect(x: okX, y: barY, width: okW, height: barH)
                    ctx.fill(Path(okRect), with: .color(Color.green.opacity(0.32)))
                }

                // High zone (red)
                let hiX = w * highFrac
                let hiW = w * (1 - highFrac)
                if hiW > 0 {
                    let hiRect = CGRect(x: hiX, y: barY, width: hiW, height: barH)
                    let hiPath = Path(roundedRect: hiRect, cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 5, topTrailing: 5))
                    ctx.fill(hiPath, with: .color(Color.red.opacity(0.32)))
                }

                // Tick marks
                drawTick(ctx: ctx, x: w * lowFrac, barY: barY, barH: barH, color: .orange)
                drawTick(ctx: ctx, x: w * highFrac, barY: barY, barH: barH, color: .red)
            }

            // Floating labels (SwiftUI overlays for crisp text)
            floatingLabel(fmtValue(low), at: w * lowFrac, geo: geo)
            floatingLabel(fmtValue(high), at: w * highFrac, geo: geo)
        }
        .frame(height: 34) // 24 for label area + 10 for bar
    }

    private func drawTick(ctx: GraphicsContext, x: CGFloat, barY: CGFloat, barH: CGFloat, color: Color) {
        let tickW: CGFloat = 2
        let tickH: CGFloat = barH + 4
        let tickY = barY - 2
        let tickRect = CGRect(x: x - tickW / 2, y: tickY, width: tickW, height: tickH)
        let tickPath = Path(roundedRect: tickRect, cornerRadius: 1)

        // White outline for contrast
        let outlineRect = CGRect(x: x - tickW / 2 - 0.5, y: tickY - 0.5, width: tickW + 1, height: tickH + 1)
        ctx.fill(Path(roundedRect: outlineRect, cornerRadius: 1.5), with: .color(Color(nsColor: .controlBackgroundColor)))
        ctx.fill(tickPath, with: .color(color))
    }

    private func floatingLabel(_ text: String, at x: CGFloat, geo: GeometryProxy) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .position(x: x, y: 8)
    }
}

// MARK: - Shortcut Keycaps

struct ShortcutKeycaps: View {
    @State private var isRecording = false
    @State private var displayString = HotkeyManager.shared.displayString

    var body: some View {
        HStack(spacing: 4) {
            if HotkeyManager.shared.isSet && !isRecording {
                let keys = parseKeys(displayString)
                ForEach(keys, id: \.self) { key in
                    keycap(key)
                }
            } else if isRecording {
                Text("Press keys...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("None")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button(action: {
                isRecording.toggle()
            }) {
                Image(systemName: isRecording ? "escape" : "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(isRecording ? .primary : .tertiary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRecording ? Color.gray.opacity(0.16) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if HotkeyManager.shared.isSet && !isRecording {
                Button(action: {
                    HotkeyManager.shared.clear()
                    displayString = "None"
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            HotkeyRecorderHelper(isRecording: $isRecording, displayString: $displayString)
        )
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.16))
                    .shadow(color: .black.opacity(0.06), radius: 0, y: 1)
            )
    }

    private func parseKeys(_ str: String) -> [String] {
        guard str != "None" else { return [] }
        var keys: [String] = []
        var remaining = str
        let modifiers = ["⌃", "⌥", "⇧", "⌘"]
        for mod in modifiers {
            if remaining.hasPrefix(mod) {
                keys.append(mod)
                remaining.removeFirst(mod.count)
            }
        }
        if !remaining.isEmpty {
            keys.append(remaining)
        }
        return keys
    }
}

// MARK: - Reusable Components

struct SettingsSection<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)

                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 10)

            content()
        }
    }
}

struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))

                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 80, alignment: .leading)

            HStack {
                Spacer()
                content()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
