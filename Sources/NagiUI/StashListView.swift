import NagiCore
import SwiftUI

/// The list of parked drafts ("退避"), newest first. Click to resume, trash to drop.
struct StashListView: View {
    let session: DraftSession

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if session.stashes.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("退避した下書きはありません")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("⌘⇧S で書きかけを退避できます")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(session.stashes) { draft in
                    StashRow(
                        draft: draft,
                        onOpen: { env.openStash(draft.id) },
                        onDiscard: { env.discardStash(draft.id) }
                    )
                    Divider().padding(.leading, 12)
                }
            }
        }
    }
}

private struct StashRow: View {
    let draft: Draft
    let onOpen: () -> Void
    let onDiscard: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(Self.relativeFormatter.localizedString(for: draft.updatedAt, relativeTo: Date()))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if isHovering {
                Button(role: .destructive, action: onDiscard) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("この下書きを破棄")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter
    }()
}
