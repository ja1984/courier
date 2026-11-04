import SwiftUI

enum SettingsKey {
    static let maskSensitiveHeaders = "maskSensitiveHeaders"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.maskSensitiveHeaders) private var maskSensitiveHeaders = true

    var body: some View {
        Form {
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
