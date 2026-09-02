import SwiftUI
import UserNotifications

enum OnboardingStep: Int, CaseIterable {
    case welcome, source, credentials, notifications, range, done
}

struct OnboardingView: View {
    @ObservedObject var glucose: GlucoseManager
    var onFinish: () -> Void

    @AppStorage("alerts_enabled") private var alertsEnabled = false

    @State private var step: OnboardingStep = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var region = "us"
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
            stepIndicator
                .padding(.top, 18)
                .padding(.bottom, 8)

            ScrollView {
                stepContent
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }

            Divider()
            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 520, height: 480)
        .background(.regularMaterial)
        .onAppear {
            email = glucose.email
            region = glucose.region
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .source: sourceStep
        case .credentials: credentialsStep
        case .notifications: notificationsStep
        case .range: rangeStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.37, green: 0.61, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.blue.opacity(0.3), radius: 10, y: 4)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.top, 24)

            Text("Welcome to LibreBar")
                .font(.system(size: 24, weight: .bold))

            Text("Your glucose, always a glance away in the menu bar. Let's get you set up in a few quick steps.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Choose your data source", "Where should LibreBar get your glucose readings?")

            Picker("", selection: $glucose.dataSource) {
                Text("LibreLinkUp").tag("libre")
                Text("Nightscout").tag("nightscout")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(glucose.isNightscout
                 ? "Connect to your own Nightscout instance using its URL and an optional access token."
                 : "Connect using your LibreLinkUp account — the same login you use in the LibreLinkUp app.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Connect your account",
                       glucose.isNightscout ? "Enter your Nightscout details." : "Enter your LibreLinkUp credentials.")

            Card {
                VStack(spacing: 12) {
                    if glucose.isNightscout {
                        labeledField("URL") {
                            TextField("https://your-site.herokuapp.com", text: $glucose.nightscoutURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("Token") {
                            SecureField("Optional", text: $glucose.nightscoutToken)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        labeledField("Email") {
                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("Password") {
                            SecureField("Required", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("Region") {
                            Picker("", selection: $region) {
                                ForEach(regions, id: \.0) { r in
                                    Text(r.1).tag(r.0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }

            connectRow
        }
    }

    private var connectRow: some View {
        HStack {
            if let error = glucose.errorMessage, connectState == .idle {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else if connectState == .connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }
            Spacer()
            Button(action: performConnect) {
                HStack(spacing: 6) {
                    if connectState == .connecting {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Connecting…")
                    } else {
                        Image(systemName: "link")
                        Text("Connect")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(minWidth: 130, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(isConnectDisabled)
            .opacity(isConnectDisabled ? 0.45 : 1.0)
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Stay informed", "LibreBar can send macOS notifications when your glucose goes out of range, including an urgent alert for very low or high readings.")

            Button {
                AlertManager.shared.requestAuthorization { granted in
                    if granted {
                        alertsEnabled = true
                        AlertManager.shared.sendTest()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                    Text("Enable & Send Test")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(minWidth: 170, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
            }
            .buttonStyle(.plain)

            Text("You can fine-tune which alerts you receive later in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var rangeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Units & target range", "Set your preferred units and the glucose range you consider in-target.")

            Picker("", selection: $glucose.useMgdl) {
                Text("mmol/L").tag(false)
                Text("mg/dL").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Card(padding: 0) {
                TargetRangeControls(
                    low: $glucose.lowThreshold,
                    high: $glucose.highThreshold,
                    useMgdl: glucose.useMgdl
                )
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 28)

            Text("You're all set")
                .font(.system(size: 22, weight: .bold))

            Text("LibreBar is now running in your menu bar. Click the reading any time to see your graph, stats, and predictions.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if step != .welcome {
                Button("Back") { goBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if canSkip {
                Button("Skip") { goNext() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Button(step == .done ? "Finish" : "Next") {
                if step == .done { onFinish() } else { goNext() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed)
        }
    }

    // MARK: - Helpers

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)
            content()
        }
    }

    private var canSkip: Bool {
        step == .notifications
    }

    private var canProceed: Bool {
        switch step {
        case .credentials:
            return glucose.latestReading != nil
        default:
            return true
        }
    }

    private var isConnectDisabled: Bool {
        if connectState != .idle { return true }
        return glucose.isNightscout ? glucose.nightscoutURL.isEmpty : (email.isEmpty || password.isEmpty)
    }

    private func goNext() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = prev }
    }

    private func performConnect() {
        guard connectState == .idle else { return }
        withAnimation(.easeInOut(duration: 0.26)) { connectState = .connecting }

        Task {
            if glucose.isNightscout {
                await glucose.fetchGlucose()
            } else {
                await glucose.configureAndFetch(email: email, password: password, region: region)
            }
            let succeeded = glucose.errorMessage == nil && glucose.latestReading != nil
            withAnimation(.easeInOut(duration: 0.26)) {
                connectState = succeeded ? .connected : .idle
            }
        }
    }
}
