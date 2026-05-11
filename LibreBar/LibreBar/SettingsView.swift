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
        Form {
            Section("Data Source") {
                Picker("Source", selection: $glucose.dataSource) {
                    Text("LibreLinkUp").tag("libre")
                    Text("Nightscout").tag("nightscout")
                }
                .pickerStyle(.segmented)
                .onChange(of: glucose.dataSource) { _, _ in
                    glucose.clearData()
                    Task { await glucose.fetchGlucose() }
                }
            }

            if glucose.isNightscout {
                Section("Nightscout") {
                    TextField("URL", text: $glucose.nightscoutURL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Token (optional)", text: $glucose.nightscoutToken)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Section("LibreLinkUp Credentials") {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    Picker("Region", selection: $region) {
                        ForEach(regions, id: \.0) { r in
                            Text(r.1).tag(r.0)
                        }
                    }
                }

                if glucose.connections.count > 1 {
                    Section("Connection") {
                        Picker("Monitor", selection: $glucose.selectedConnectionId) {
                            ForEach(glucose.connections) { conn in
                                Text(conn.displayName).tag(conn.id)
                            }
                        }
                        .onChange(of: glucose.selectedConnectionId) { _, _ in
                            Task { await glucose.fetchGlucose() }
                        }
                    }
                }
            }

            Section("Units") {
                Picker("Glucose Unit", selection: $glucose.useMgdl) {
                    Text("mmol/L").tag(false)
                    Text("mg/dL").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Target Range (\(glucose.useMgdl ? "mg/dL" : "mmol/L"))") {
                if glucose.useMgdl {
                    let lowBinding = Binding<Double>(
                        get: { glucose.lowThreshold * 18.0182 },
                        set: { glucose.lowThreshold = $0 / 18.0182 }
                    )
                    let highBinding = Binding<Double>(
                        get: { glucose.highThreshold * 18.0182 },
                        set: { glucose.highThreshold = $0 / 18.0182 }
                    )
                    HStack {
                        Text("Low")
                        Slider(value: lowBinding, in: 36...108, step: 1)
                        Text("\(lowBinding.wrappedValue, specifier: "%.0f")")
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                    }
                    HStack {
                        Text("High")
                        Slider(value: highBinding, in: 108...288, step: 1)
                        Text("\(highBinding.wrappedValue, specifier: "%.0f")")
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                    }
                } else {
                    HStack {
                        Text("Low")
                        Slider(value: $glucose.lowThreshold, in: 2.0...6.0, step: 0.1)
                        Text("\(glucose.lowThreshold, specifier: "%.1f")")
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                    }
                    HStack {
                        Text("High")
                        Slider(value: $glucose.highThreshold, in: 6.0...16.0, step: 0.1)
                        Text("\(glucose.highThreshold, specifier: "%.1f")")
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }

            Section("Menu Bar") {
                Toggle("Color indicator dot", isOn: $glucose.showColorDot)
                Toggle("Mini sparkline graph", isOn: $glucose.showSparkline)
            }

            Section("Graph") {
                Toggle("Min/Max markers", isOn: $glucose.showMinMax)
                Toggle("Prediction line", isOn: $glucose.showPredictionLine)
            }

            Section("Keyboard Shortcut") {
                HotkeyRecorderView()
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
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

            Button(saved ? "Saved!" : "Save & Connect") {
                if glucose.isNightscout {
                    Task { await glucose.fetchGlucose() }
                } else {
                    glucose.configure(email: email, password: password, region: region)
                }
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
            }
            .disabled(glucose.isNightscout ? glucose.nightscoutURL.isEmpty : (email.isEmpty || password.isEmpty))

            if let error = glucose.errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            email = glucose.email
            region = glucose.region
        }
    }
}
