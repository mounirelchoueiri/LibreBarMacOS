import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var glucose: GlucoseManager
    @State private var email = ""
    @State private var password = ""
    @State private var region = "us"
    @State private var saved = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
        VStack(spacing: 14) {
            // ROW 1: Connection (left) + Preferences (right)
            HStack(alignment: .top, spacing: 12) {
                // LEFT COLUMN
                VStack(spacing: 12) {
                settingsCard {
                    sectionHeader("Data Source", icon: "antenna.radiowaves.left.and.right")
                    Picker("Source", selection: $glucose.dataSource) {
                        Text("LibreLinkUp").tag("libre")
                        Text("Nightscout").tag("nightscout")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: glucose.dataSource) { _, _ in
                        glucose.clearData()
                        Task { await glucose.fetchGlucose() }
                    }

                    Divider().padding(.vertical, 2)

                    if glucose.isNightscout {
                        sectionHeader("Nightscout", icon: "globe")
                        settingsField("URL", text: $glucose.nightscoutURL)
                        settingsSecureField("Token (optional)", text: $glucose.nightscoutToken)
                    } else {
                        sectionHeader("LibreLinkUp", icon: "person.crop.circle")
                        settingsField("Email", text: $email)
                        settingsSecureField("Password", text: $password)
                        Picker("Region", selection: $region) {
                            ForEach(regions, id: \.0) { r in
                                Text(r.1).tag(r.0)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)

                        if glucose.connections.count > 1 {
                            Divider().padding(.vertical, 2)
                            HStack {
                                Text("Monitor")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                Spacer()
                                Picker("", selection: $glucose.selectedConnectionId) {
                                    ForEach(glucose.connections) { conn in
                                        Text(conn.displayName).tag(conn.id)
                                    }
                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .onChange(of: glucose.selectedConnectionId) { _, _ in
                                    Task { await glucose.fetchGlucose() }
                                }
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    Button(action: {
                        if glucose.isNightscout {
                            Task { await glucose.fetchGlucose() }
                        } else {
                            glucose.configure(email: email, password: password, region: region)
                        }
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: saved ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            Text(saved ? "Connected!" : "Save & Connect")
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(saved ? .green : .blue)
                    .controlSize(.small)
                    .disabled(glucose.isNightscout ? glucose.nightscoutURL.isEmpty : (email.isEmpty || password.isEmpty))

                    if let error = glucose.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption2)
                    }
                }

                settingsCard {
                    sectionHeader("General", icon: "gearshape")
                    toggleRow("Launch at Login", isOn: $launchAtLogin)
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

                    Button(action: {
                        UpdateChecker.shared.checkForUpdates(silent: false)
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                            Text("Check for Updates")
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                }
                .frame(maxWidth: .infinity)


                // Preferences
                VStack(spacing: 12) {
                    settingsCard {
                        sectionHeader("Units", icon: "ruler")
                        Picker("", selection: $glucose.useMgdl) {
                            Text("mmol/L").tag(false)
                            Text("mg/dL").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    HStack(spacing: 12) {
                        settingsCard {
                            sectionHeader("Menu Bar", icon: "menubar.rectangle")
                            toggleRow("Color dot", isOn: $glucose.showColorDot)
                            toggleRow("Sparkline", isOn: $glucose.showSparkline)
                        }

                        settingsCard {
                            sectionHeader("Graph", icon: "chart.xyaxis.line")
                            toggleRow("Min/Max", isOn: $glucose.showMinMax)
                            toggleRow("Prediction", isOn: $glucose.showPredictionLine)
                        }
                    }

                    settingsCard {
                        sectionHeader("Shortcut", icon: "keyboard")
                        HotkeyRecorderView()
                    }

                }
            }

            // ROW 2: Target Range (full width)
            settingsCard {
                sectionHeader("Target Range", icon: "target")
                HStack {
                    Text(glucose.useMgdl ? "mg/dL" : "mmol/L")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                if glucose.useMgdl {
                    let lowBinding = Binding<Double>(
                        get: { glucose.lowThreshold * 18.0182 },
                        set: { glucose.lowThreshold = $0 / 18.0182 }
                    )
                    let highBinding = Binding<Double>(
                        get: { glucose.highThreshold * 18.0182 },
                        set: { glucose.highThreshold = $0 / 18.0182 }
                    )
                    sliderRow(label: "Low", color: .orange, value: lowBinding, range: 36...108, step: 1, format: "%.0f")
                    sliderRow(label: "High", color: .red, value: highBinding, range: 108...288, step: 1, format: "%.0f")
                } else {
                    sliderRow(label: "Low", color: .orange, value: $glucose.lowThreshold, range: 2.0...6.0, step: 0.1, format: "%.1f")
                    sliderRow(label: "High", color: .red, value: $glucose.highThreshold, range: 6.0...16.0, step: 0.1, format: "%.1f")
                }
            }

            // Footer
            Text("LibreBar v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(minWidth: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            email = glucose.email
            region = glucose.region
        }
    }

    // MARK: - Components

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
            Text(title)
                .font(.system(.body, weight: .semibold))
        }
        .padding(.bottom, 2)
    }

    private func settingsField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
    }

    private func settingsSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
    }

    private func sliderRow(label: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.callout)
            }
            .frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit()
                .font(.callout)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
