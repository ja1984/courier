import CourierCore
import SwiftUI

/// The request's Cookies tab: its own cookies (editable, like headers), and below them the
/// cookie jar's cookies that will be sent to this URL, which can be edited or deleted too.
struct CookiesEditor: View {
    @Bindable var tab: RequestTab
    let store: AppStore
    @AppStorage(SettingsKey.rememberCookies) private var rememberCookies = true

    /// The URL as it will be sent (same rules as `HTTPClient.makeURLRequest`).
    static func url(for spec: RequestSpec) -> URL? {
        var raw = spec.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        guard let url = URL(string: raw), url.host() != nil else { return nil }
        return url
    }

    /// How many cookies the request will send: its own plus matching jar cookies, merged by name.
    static func sentCount(spec: RequestSpec, store: AppStore) -> Int {
        let jar = store.rememberCookies ? url(for: spec).map { store.cookieJar.cookies(for: $0) } ?? [] : []
        let pairs = jar.map { CookiePair(name: $0.name, value: $0.value) } + spec.requestCookies
        return CookiePair.merged(pairs).count
    }

    private var url: URL? { Self.url(for: tab.spec) }

    private var jarCookies: [StoredCookie] {
        url.map { store.cookieJar.cookies(for: $0) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            KeyValueEditor(
                title: "Request Cookies",
                items: $tab.spec.cookies,
                note: "Sent in the Cookie header, and saved with the request",
                masksSecrets: true,
                masksAllValues: true
            )
            .frame(minHeight: 120)

            jarSection
        }
    }

    @ViewBuilder
    private var jarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(url?.host().map { "Cookie Jar · \($0)" } ?? "Cookie Jar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if rememberCookies, !jarCookies.isEmpty {
                    Button("Clear") {
                        for cookie in jarCookies { store.deleteCookie(cookie.id) }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .tooltip("Delete the \(jarCookies.count == 1 ? "cookie" : "\(jarCookies.count) cookies") sent to this URL")
                }
            }

            if !rememberCookies {
                note("The cookie jar is off, so only the cookies above are sent.") {
                    SettingsLink { Text("Turn On in Settings…") }
                        .buttonStyle(.link)
                }
            } else if jarCookies.isEmpty {
                note(
                    url == nil
                        ? "Enter a URL to see the stored cookies that will be sent to it."
                        : "No stored cookies for this URL yet. Cookies the server sets will appear here and be sent next time."
                ) { EmptyView() }
            } else {
                let overridden = Set(tab.spec.requestCookies.map(\.name))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(jarCookies.enumerated()), id: \.element.id) { index, cookie in
                            if index > 0 { Divider() }
                            JarCookieRow(cookie: cookie, isOverridden: overridden.contains(cookie.name), store: store)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(1)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 190)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func note(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(text)
            action()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

private struct JarCookieRow: View {
    let cookie: StoredCookie
    let isOverridden: Bool
    let store: AppStore
    @State private var isHovering = false
    @State private var isHoveringValue = false
    @FocusState private var valueIsFocused: Bool
    @AppStorage(SettingsKey.maskSensitiveHeaders) private var maskSetting = true

    private var isMasked: Bool {
        maskSetting && !isHoveringValue && !valueIsFocused && !cookie.value.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(cookie.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 140, alignment: .leading)
                .strikethrough(isOverridden)

            TextField(
                "Value",
                text: Binding(get: { cookie.value }, set: { store.setCookieValue($0, for: cookie.id) })
            )
            .textFieldStyle(.plain)
            .focused($valueIsFocused)
            .opacity(isMasked ? 0 : 1)
            .overlay(alignment: .leading) {
                if isMasked {
                    Text(SensitiveHeaders.mask)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Hidden value")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHoveringValue = $0 }
            .help(isMasked ? "Hidden. Hover to show." : "Editing changes the stored cookie for every request to \(cookie.domain)")

            if isOverridden {
                CookieBadge(text: "Overridden")
                    .help("A request cookie with the same name is sent instead")
            }
            Text(CookieDescription.scope(cookie))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help(CookieDescription.details(cookie))

            Button {
                store.deleteCookie(cookie.id)
            } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
            .tooltip("Delete “\(cookie.name)” from the cookie jar")
            .accessibilityLabel("Delete \(cookie.name)")
        }
        .font(.system(size: 12))
        .opacity(isOverridden ? 0.55 : 1)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(isHovering ? Color.primary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// The cookies a response set, with their attributes.
struct ResponseCookiesList: View {
    let cookies: [StoredCookie]
    @AppStorage(SettingsKey.rememberCookies) private var rememberCookies = true

    var body: some View {
        if cookies.isEmpty {
            ContentUnavailableView(
                "No Cookies",
                systemImage: "circle.dotted",
                description: Text("The response didn't set any cookies.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(rememberCookies
                         ? "Saved to the cookie jar and sent with later requests to these domains."
                         : "Not saved: the cookie jar is off in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                    ForEach(Array(cookies.enumerated()), id: \.offset) { index, cookie in
                        if index > 0 { Divider() }
                        ResponseCookieRow(cookie: cookie)
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct ResponseCookieRow: View {
    let cookie: StoredCookie
    @State private var isHoveringValue = false
    @AppStorage(SettingsKey.maskSensitiveHeaders) private var maskSetting = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(cookie.name).fontWeight(.semibold)
                Group {
                    if cookie.value.isEmpty {
                        Text("empty").italic().foregroundStyle(.tertiary)
                    } else if maskSetting && !isHoveringValue {
                        Text(SensitiveHeaders.mask).foregroundStyle(.secondary)
                    } else {
                        Text(cookie.value).textSelection(.enabled)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { isHoveringValue = $0 }
            }
            .font(.system(size: 12, design: .monospaced))

            HStack(spacing: 6) {
                Text(CookieDescription.scope(cookie))
                Text("·")
                Text(CookieDescription.expiry(cookie))
                ForEach(CookieDescription.flags(cookie), id: \.self) { CookieBadge(text: $0) }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct CookieBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

enum CookieDescription {
    /// "example.com/api" or ".example.com" for cookies that include subdomains.
    static func scope(_ cookie: StoredCookie) -> String {
        (cookie.hostOnly ? "" : ".") + cookie.domain + (cookie.path == "/" ? "" : cookie.path)
    }

    static func expiry(_ cookie: StoredCookie) -> String {
        guard let expires = cookie.expires else { return "Session" }
        if expires <= Date() { return "Expired" }
        return "Expires " + expires.formatted(date: .abbreviated, time: .shortened)
    }

    static func flags(_ cookie: StoredCookie) -> [String] {
        var flags: [String] = []
        if cookie.secure { flags.append("Secure") }
        if cookie.httpOnly { flags.append("HttpOnly") }
        if let sameSite = cookie.sameSite, !sameSite.isEmpty { flags.append("SameSite=\(sameSite.capitalized)") }
        return flags
    }

    static func details(_ cookie: StoredCookie) -> String {
        ([scope(cookie), expiry(cookie)] + flags(cookie)).joined(separator: " · ")
    }
}
