import CourierCore
import SwiftUI

private enum RequestSection: String, CaseIterable, Identifiable {
    case params, headers, body
    var id: String { rawValue }
}

struct RequestWorkspace: View {
    @Bindable var tab: RequestTab
    let store: AppStore
    @State private var section: RequestSection

    init(tab: RequestTab, store: AppStore) {
        self.tab = tab
        self.store = store
        _section = State(initialValue: tab.spec.bodyKind == .none ? .params : .body)
    }

    private var paramsBinding: Binding<[KeyValue]> {
        Binding(get: { tab.spec.params }, set: { tab.spec.setParams($0) })
    }

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 10) {
                URLBar(tab: tab, store: store)
                Picker("Section", selection: $section) {
                    ForEach(RequestSection.allCases) { item in
                        Text(label(for: item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Edit query parameters, headers or body")

                Group {
                    switch section {
                    case .params:
                        KeyValueEditor(title: "Query Params", items: paramsBinding)
                    case .headers:
                        KeyValueEditor(
                            title: "Headers",
                            items: $tab.spec.headers,
                            note: "Content-Type is added automatically for bodies"
                        )
                    case .body:
                        BodyEditor(spec: $tab.spec)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(14)
            .frame(minHeight: 200, idealHeight: 300)
            .background(Theme.content)

            ResponsePanel(tab: tab)
                .frame(minHeight: 200)
        }
        // Persisting is a side effect of editing, so it can't be a computed value.
        .onChange(of: tab.spec) { store.scheduleTabsSave() }
    }

    private func label(for item: RequestSection) -> String {
        switch item {
        case .params:
            let count = tab.spec.params.filter { $0.isEnabled && !$0.key.isEmpty }.count
            return count > 0 ? "Params (\(count))" : "Params"
        case .headers:
            let count = tab.spec.enabledHeaders.count
            return count > 0 ? "Headers (\(count))" : "Headers"
        case .body:
            return tab.spec.bodyKind == .none ? "Body" : "Body · \(tab.spec.bodyKind.title)"
        }
    }
}

private struct URLBar: View {
    @Bindable var tab: RequestTab
    let store: AppStore
    @FocusState private var isURLFocused: Bool
    @State private var didCopy = false

    private var isURLEmpty: Bool { tab.spec.url.trimmingCharacters(in: .whitespaces).isEmpty }

    private var methods: [HTTPMethod] {
        HTTPMethod.common.contains(tab.spec.method) ? HTTPMethod.common : HTTPMethod.common + [tab.spec.method]
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(methods) { method in
                        Button(method.rawValue) { tab.spec.method = method }
                    }
                } label: {
                    MethodLabel(method: tab.spec.method, size: 13)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.leading, 12)
                .help("HTTP method")
                .accessibilityLabel("HTTP method \(tab.spec.method.rawValue)")

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 10)

                TextField(
                    "Enter a URL or paste a cURL command",
                    text: Binding(get: { tab.spec.url }, set: { tab.updateURL($0) })
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($isURLFocused)
                // The whole bar draws the focus ring; without this the field adds a second one.
                .focusEffectDisabled()
                .onSubmit { store.send(tab) }
                .padding(.trailing, 10)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(Capsule().fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                Capsule().strokeBorder(isURLFocused ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
            )
            // Soft outer ring like the system focus ring.
            .background(
                Capsule()
                    .stroke(Color.accentColor.opacity(isURLFocused ? 0.3 : 0), lineWidth: 3.5)
                    .padding(-1.5)
            )
            .animation(.easeOut(duration: 0.15), value: isURLFocused)

            if tab.isLoading {
                Button("Cancel", role: .cancel) { tab.cancel() }
                    .controlSize(.large)
                    .help("Cancel request (⌘.)")
            } else {
                Button {
                    store.send(tab)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isURLEmpty)
                .help(isURLEmpty ? "Enter a URL to send" : "Send request (⌘↩)")
            }

            Button {
                store.copyAsCurl(tab.spec)
                didCopy = true
            } label: {
                Image(systemName: didCopy ? "checkmark" : "terminal")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .controlSize(.large)
            .disabled(isURLEmpty)
            .help(didCopy ? "Copied" : "Copy as cURL (⇧⌘C)")
            .accessibilityLabel(didCopy ? "Copied as cURL" : "Copy as cURL")
            // Reverts the checkmark; cancelled automatically if the view goes away.
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        }
        .onAppear {
            if tab.spec.url.isEmpty { isURLFocused = true }
        }
    }
}
