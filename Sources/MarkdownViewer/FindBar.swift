import SwiftUI

/// The find / find-and-replace bar, shown above the document content in both the
/// rendered preview and the raw editor. Pure UI — every action goes through
/// `FindController`, which knows which surface it is searching and whether
/// replacing is possible there.
struct FindBar: View {
    @ObservedObject var find: FindController
    @FocusState private var focus: Field?

    private enum Field: Hashable { case query, replacement }

    private var noQuery: Bool { find.query.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find", text: $find.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .query)
                    .frame(minWidth: 140, idealWidth: 220, maxWidth: 320)
                    .onSubmit { find.findNext() }

                Toggle(isOn: $find.caseSensitive) {
                    Text("Aa").font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.button)
                .help("Match case")

                Button { find.findPrevious() } label: { Image(systemName: "chevron.up") }
                    .disabled(noQuery)
                    .help("Find previous (⇧⌘G)")

                Button { find.findNext() } label: { Image(systemName: "chevron.down") }
                    .disabled(noQuery)
                    .help("Find next (⌘G)")

                Text(find.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 8)

                // Escape closes the bar and returns focus to the document.
                Button("Done") { find.close() }
                    .keyboardShortcut(.cancelAction)
            }

            if find.showsReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundStyle(.secondary)

                    TextField("Replace", text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .replacement)
                        .frame(minWidth: 140, idealWidth: 220, maxWidth: 320)
                        .onSubmit { find.replaceCurrent() }

                    Button("Replace") { find.replaceCurrent() }
                        .disabled(noQuery)
                    Button("All") { find.replaceAll() }
                        .disabled(noQuery)
                        .help("Replace every match in one step")

                    Spacer(minLength: 8)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        // Opening the bar (and every further ⌘F) puts the keyboard in the search
        // field; the hop lets SwiftUI finish installing the field first.
        .onAppear { focusQuery() }
        .onChange(of: find.focusRequest) { _ in focusQuery() }
        // Search as you type, and re-run when the case toggle flips.
        .onChange(of: find.query) { _ in find.runIncremental() }
        .onChange(of: find.caseSensitive) { _ in find.runIncremental() }
    }

    private func focusQuery() {
        DispatchQueue.main.async { focus = .query }
    }
}
