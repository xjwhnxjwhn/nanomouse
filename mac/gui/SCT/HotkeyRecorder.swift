import SwiftUI
import AppKit

struct HotkeyRecorder: View {
    @Binding var hotkey: String
    @State private var isRecording = false
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var recordedKey: String = ""

    var body: some View {
        Button(action: {
            isRecording.toggle()
            if isRecording {
                recordedModifiers = []
                recordedKey = ""
            }
        }) {
            HStack {
                if isRecording {
                    Text(currentStrokeString.isEmpty ? L10n.pressKey : currentStrokeString)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(hotkey.isEmpty ? L10n.clickToRecord : hotkey)
                }

                if isRecording {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .background(HotkeyMonitorView(isRecording: $isRecording) { modifiers, key in
            self.recordedModifiers = modifiers
            self.recordedKey = key
            self.hotkey = formatRimeHotkey(modifiers: modifiers, key: key)
            self.isRecording = false
        })
    }

    private var currentStrokeString: String {
        formatRimeHotkey(modifiers: recordedModifiers, key: recordedKey)
    }

    private func formatRimeHotkey(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.command) { parts.append("Command") }

        if !key.isEmpty {
            parts.append(key)
        }

        return parts.joined(separator: "+")
    }
}

private struct HotkeyMonitorView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCaptured: (NSEvent.ModifierFlags, String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            context.coordinator.startMonitoring(onCaptured: onCaptured)
        } else {
            context.coordinator.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording)
    }

    class Coordinator: NSObject {
        @Binding var isRecording: Bool
        var monitor: Any?

        init(isRecording: Binding<Bool>) {
            _isRecording = isRecording
        }

        func startMonitoring(onCaptured: @escaping (NSEvent.ModifierFlags, String) -> Void) {
            stopMonitoring()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if event.type == .flagsChanged {
                    // Just update UI if we wanted to show modifiers being held
                    return event
                }

                if event.type == .keyDown {
                    let modifiers = event.modifierFlags
                    let key = self.translateKey(event: event)

                    if !key.isEmpty {
                        onCaptured(modifiers, key)
                        return nil // Swallow the event
                    }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func translateKey(event: NSEvent) -> String {
            // Rime specific key names
            let specialKeys: [UInt16: String] = [
                50: "grave",
                36: "Return",
                48: "Tab",
                49: "space",
                51: "BackSpace",
                53: "Escape",
                123: "Left",
                124: "Right",
                125: "Down",
                126: "Up",
                116: "Page_Up",
                121: "Page_Down",
                115: "Home",
                119: "End",
                117: "Delete",
                122: "F1",
                120: "F2",
                99: "F3",
                118: "F4",
                96: "F5",
                97: "F6",
                98: "F7",
                100: "F8",
                101: "F9",
                109: "F10",
                103: "F11",
                111: "F12"
            ]

            if let special = specialKeys[event.keyCode] {
                return special
            }

            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                let char = chars.first!
                let charMap: [Character: String] = [
                    "`": "grave",
                    "-": "minus",
                    "=": "equal",
                    "[": "bracketleft",
                    "]": "bracketright",
                    "\\": "backslash",
                    ";": "semicolon",
                    "'": "apostrophe",
                    ",": "comma",
                    ".": "period",
                    "/": "slash",
                    " ": "space"
                ]
                return charMap[char] ?? String(char)
            }
            return ""
        }
    }
}
