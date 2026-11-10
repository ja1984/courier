import AppKit
import SwiftUI

enum SettingsKey {
    static let maskSensitiveHeaders = "maskSensitiveHeaders"
    static let appearance = "appearance"
    static let rememberCookies = "rememberCookies"
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
    let store: AppStore
    @AppStorage(SettingsKey.maskSensitiveHeaders) private var maskSensitiveHeaders = true
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system
    @AppStorage(SettingsKey.rememberCookies) private var rememberCookies = true
    @State private var isConfirmingClearCookies = false

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
            Section("Cookies") {
                Toggle(isOn: $rememberCookies) {
                    Text("Remember cookies from responses")
                    Text("Cookies a server sets are kept per domain, encrypted, and sent with later requests to it, like a browser. Edit them in a request's Cookies tab.")
                }
                HStack {
                    let count = store.cookieJar.cookies.count
                    Text(count == 1 ? "1 cookie stored" : "\(count) cookies stored")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All Cookies…") { isConfirmingClearCookies = true }
                        .disabled(count == 0)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all cookies?", isPresented: $isConfirmingClearCookies) {
            Button("Clear All Cookies", role: .destructive) { store.clearAllCookies() }
        } message: {
            Text("You'll be logged out of anything that relied on them.")
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
