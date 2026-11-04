import AppKit
import SwiftUI

enum SettingsKey {
    static let maskSensitiveHeaders = "maskSensitiveHeaders"
    static let appearance = "appearance"
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applied app-wide, so AppKit views (code editor, popovers, menus, Settings) follow too.
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.maskSensitiveHeaders) private var maskSensitiveHeaders = true
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system

    var body: some View {
        Form {
            Section("Appearance") {
                // Centered rather than baseline-aligned: the segmented control's text sits low
                // in its frame, so baseline alignment leaves it visibly high in the row.
                HStack(alignment: .center) {
                    Text("Theme")
                    Spacer()
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Auto follows the macOS Light/Dark setting")
                }
            }
            Section("Privacy") {
                Toggle(isOn: $maskSensitiveHeaders) {
                    Text("Hide secret header values")
                    Text("Values of headers like Authorization, Cookie, X-API-Key and anything with “token” or “secret” in its name show as dots until you hover over them.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
