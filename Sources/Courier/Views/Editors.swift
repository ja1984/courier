import CourierCore
import SwiftUI

/// A key/value table with a section title and a trailing empty row.
/// Typing into the empty row turns it into a real row; a new empty row appears below.
struct KeyValueEditor: View {
    let title: String
    @Binding var items: [KeyValue]
    var note: String?

    /// Id of the trailing placeholder row. When it's edited, the new item takes this id,
    /// so SwiftUI keeps the same row (and keyboard focus) while a fresh placeholder appears.
    @State private var placeholderID = UUID()

    private static let checkboxWidth: CGFloat = 34
    private static let deleteWidth: CGFloat = 30

    private var rows: [KeyValue] { items + [KeyValue(id: placeholderID)] }

    private func binding(for id: UUID) -> Binding<KeyValue> {
        Binding(
            get: { items.first { $0.id == id } ?? KeyValue(id: id) },
            set: { newValue in
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index] = newValue
                } else if !newValue.key.isEmpty || !newValue.value.isEmpty {
                    items.append(newValue)
                    placeholderID = UUID()
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(rows) { row in
                        Divider()
                        KeyValueRow(
                            item: binding(for: row.id),
                            isPlaceholder: row.id == placeholderID,
                            onDelete: { items.removeAll { $0.id == row.id } }
                        )
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
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.checkboxWidth)
            Divider()
            Text("Key").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            Divider()
            Text("Value").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            Color.clear.frame(width: Self.deleteWidth)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(height: 30)
        .background(Color.primary.opacity(0.025))
    }

    fileprivate static func columns(checkbox: some View, key: some View, value: some View, delete: some View) -> some View {
        HStack(spacing: 0) {
            checkbox.frame(width: checkboxWidth)
            Divider()
            key.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            Divider()
            value.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            delete.frame(width: deleteWidth)
        }
        .frame(height: 30)
    }
}

private struct KeyValueRow: View {
    @Binding var item: KeyValue
    let isPlaceholder: Bool
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        KeyValueEditor.columns(
            checkbox: Group {
                if isPlaceholder {
                    Color.clear
                } else {
                    Toggle("Enabled", isOn: $item.isEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help(item.isEnabled ? "Included. Click to disable." : "Excluded. Click to enable.")
                }
            },
            key: TextField("Key", text: $item.key)
                .textFieldStyle(.plain)
                .opacity(item.isEnabled || isPlaceholder ? 1 : 0.45),
            value: TextField("Value", text: $item.value)
                .textFieldStyle(.plain)
                .opacity(item.isEnabled || isPlaceholder ? 1 : 0.45),
            delete: Group {
                if isPlaceholder {
                    Color.clear
                } else {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .opacity(isHovering ? 1 : 0)
                    .help("Remove \(item.key.isEmpty ? "this row" : "“\(item.key)”")")
                    .accessibilityLabel("Remove \(item.key.isEmpty ? "row" : item.key)")
                }
            }
        )
        .font(.system(size: 12))
        .background(isHovering && !isPlaceholder ? Color.primary.opacity(0.03) : .clear)
        .onHover { isHovering = $0 }
    }
}

struct BodyEditor: View {
    @Binding var spec: RequestSpec

    private var jsonIsInvalid: Bool {
        spec.bodyKind == .json && !spec.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !JSONFormatter.isValid(spec.bodyText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Body type", selection: $spec.bodyKind) {
                    ForEach(BodyKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Body type. Content-Type is set automatically unless you add it in Headers.")

                Spacer()

                if jsonIsInvalid {
                    Label("Invalid JSON", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if spec.bodyKind == .json {
                    Button("Beautify") {
                        if let pretty = JSONFormatter.prettyPrinted(spec.bodyText) { spec.bodyText = pretty }
                    }
                    .controlSize(.small)
                    .disabled(jsonIsInvalid || spec.bodyText.isEmpty)
                    .help(jsonIsInvalid ? "Fix the JSON before formatting it" : "Re-indent the JSON body")
                }
            }

            switch spec.bodyKind {
            case .none:
                Text("This request has no body.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .json, .text:
                CodeTextView(text: $spec.bodyText, isEditable: true, language: spec.bodyKind == .json ? .json : .plain)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12))
                    )
            case .form:
                KeyValueEditor(title: "Form Fields", items: $spec.formFields)
            }
        }
    }
}
