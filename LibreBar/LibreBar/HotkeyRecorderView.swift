import SwiftUI
import Carbon

struct HotkeyRecorderView: View {
    @State private var isRecording = false
    @State private var displayString = HotkeyManager.shared.displayString

    var body: some View {
        HStack {
            Text("Open Popover")
            Spacer()
            Button(action: {
                if isRecording {
                    isRecording = false
                } else {
                    isRecording = true
                }
            }) {
                Text(isRecording ? "Press keys..." : displayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .background(
                HotkeyRecorderHelper(isRecording: $isRecording, displayString: $displayString)
            )

            if HotkeyManager.shared.isSet {
                Button("Clear") {
                    HotkeyManager.shared.clear()
                    displayString = "None"
                }
                .font(.caption)
            }
        }
    }
}

struct HotkeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var displayString: String

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            HotkeyManager.shared.set(keyCode: keyCode, modifiers: modifiers)
            displayString = HotkeyManager.shared.displayString
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.isRecordingActive = isRecording
    }
}

class RecorderNSView: NSView {
    var isRecordingActive = false
    var onKeyRecorded: ((Int, Int) -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingActive else { return event }

            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return event }

            self.onKeyRecorded?(Int(event.keyCode), Int(mods.rawValue))
            return nil
        }
    }

    override func removeFromSuperview() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        super.removeFromSuperview()
    }
}
