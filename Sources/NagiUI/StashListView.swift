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
            // 10pt .tertiary measured ~1.9:1 — below the minimum size *and*
            // the minimum contrast at once.
            Text("⌘⇧S で書きかけを退避できます")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(session.stashes.enumerated()), id: \.element.id) { index, draft in
                    StashRow(
                        draft: draft,
                        onOpen: { env.openStash(draft.id) },
                        onDiscard: { env.discardStash(draft.id) }
                    )
                    // Separators go *between* rows; one after the last row just
                    // draws a stray line across the bottom of the list.
                    if index < session.stashes.count - 1 {
                        Divider().padding(.leading, 12)
                    }
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
            // A real Button rather than .onTapGesture: a tap gesture takes no
            // focus and exposes no action, which left this list operable by
            // pointer only.
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    // Stated rather than inherited, so the title's contrast does
                    // not depend on what the surrounding button style supplies.
                    Text(draft.displayTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    // 10pt .tertiary measured ~1.9:1 — under the minimum size
                    // and the minimum contrast at the same time.
                    Text(Self.relativeFormatter.localizedString(
                        for: draft.updatedAt, relativeTo: Date()
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("この下書きを開く")

            // Always present, so it has a place in the focus order and the
            // accessibility tree; only its opacity follows the pointer.
            Button(role: .destructive, action: onDiscard) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .frame(width: 22, height: 22)   // desktop minimum control size is 20x20pt
            .opacity(isHovering ? 1 : 0)
            .help("この下書きを破棄")
            .accessibilityLabel("「\(draft.displayTitle)」を破棄")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { isHovering = $0 }
        // A second, deliberate route to a destructive action that otherwise
        // depends on hitting a small target that has only just faded in.
        .contextMenu {
            Button("開く", action: onOpen)
            Button("破棄", role: .destructive, action: onDiscard)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter
    }()
}
