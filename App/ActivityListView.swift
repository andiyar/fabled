import SwiftUI
import FabledCore

/// The inspector's default face (UX-LEDGER row 26): a clickable list of
/// everything that ran — one card per unit (a live tool, a subagent, a
/// collapsed run, a single tool). Clicking a card drills into that item's
/// existing detail via the injected inspect action; the panel's Back returns
/// here. Rendered to the locked mockup (`.insp` / `.insp-head` / `.act`).
struct ActivityListView: View {
    let timeline: [TimelineItem]
    let subagents: [String: [TimelineItem]]
    /// Threaded in explicitly — presentation boundaries (`.inspector`) drop
    /// `.environment` values, so rows never read the action from the env.
    let inspectItem: InspectItemAction?
    /// The header's "Clear". nil hides it.
    var onClear: (() -> Void)? = nil

    var body: some View {
        // Derive the list ONCE per render, then pass the array + its count down.
        // The header count, the empty check, and the ForEach all read this same
        // value instead of re-running ActivityList.rows three times per body.
        let rows = ActivityList.rows(timeline: timeline, subagents: subagents)
        return VStack(spacing: 0) {
            header(count: rows.count)
            if rows.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(rows) { row in
                            ActivityRowView(row: row, inspectItem: inspectItem)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Bottom-hairline header: serif "Activity", a faint count, "Clear" at right.
    private func header(count: Int) -> some View {
        HStack(spacing: 9) {
            Text("Activity")
                .font(.system(size: 14, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("\(count)")
                .font(.system(size: 11).weight(.semibold))
                .foregroundStyle(Theme.faint)
                .monospacedDigit()
            Spacer(minLength: 0)
            if let onClear {
                Text("Clear")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .contentShape(Rectangle())
                    .onTapGesture { onClear() }
                    .help("Hide the inspector")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var empty: some View {
        Text("Nothing yet — activity appears here as tools run.")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }
}

/// One activity card. Activation is a `TapGesture`, NOT a `Button`: the same
/// render-churn that cancels Button press-dispatch on transcript rows applies
/// here (the inspect action rides an environment-tagged closure whose owner
/// re-renders on every stream tick). Mirror `ToolCallCard`/`ToolGroupRow`: the
/// gesture + contentShape sit OUTSIDE padding/background so the whole card is
/// the hit target.
private struct ActivityRowView: View {
    let row: ActivityRow
    let inspectItem: InspectItemAction?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12.5).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    // Path-like titles (edit/read) truncate the HEAD so the
                    // filename at the end stays visible, matching the detail view.
                    .truncationMode(titleTruncationMode)
                HStack(spacing: 6) {
                    // A live row — a running tool OR a still-running subagent —
                    // shows the pulse beside its subtitle, so an agent row keeps
                    // its accent icon, step count, and drill chevron AND reads live.
                    if row.isLive { PulsingLiveDot() }
                    subtitle
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .padding(.top, 2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(hovering ? Theme.accentBronze.opacity(0.4) : Theme.hairline,
                        lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { inspectItem?(row.drillID) }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(row.title), \(row.subtitle)")
        .help("Show \(row.title) in the inspector")
    }

    // Every row is drillable, so the trailing affordance is always the drill
    // chevron; live-ness is shown by the pulse beside the subtitle instead (so a
    // running agent keeps its chevron rather than losing it to the dot).
    private var trailing: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.faint)
    }

    // Edit/read titles are file paths — truncate the head so the filename shows.
    private var titleTruncationMode: Text.TruncationMode {
        (row.kind == .edit || row.kind == .read) ? .head : .tail
    }

    // "+N" green / "−N" red / everything else muted, so an edit row's diff
    // counts read at a glance while "done"/"running"/"3 steps" stay quiet.
    private var subtitle: Text {
        let tokens = row.subtitle.split(separator: " ").map(String.init)
        var out = Text("")
        for (i, token) in tokens.enumerated() {
            let piece: Text
            if token.hasPrefix("+") {
                piece = Text(token).foregroundColor(Theme.diffAddColor)
            } else if token.hasPrefix("\u{2212}") {
                piece = Text(token).foregroundColor(Theme.diffDelColor)
            } else {
                piece = Text(token).foregroundColor(Theme.muted)
            }
            out = i == 0 ? piece : out + Text(" ").foregroundColor(Theme.muted) + piece
        }
        return out
    }

    private var iconName: String {
        switch row.kind {
        case .command: "terminal"
        case .edit:    "pencil"
        case .read:    "doc.text"
        case .agent:   "sparkles"
        case .live:    "livephoto"
        case .other:   "gearshape"
        }
    }

    private var iconColor: Color {
        switch row.kind {
        case .agent: Theme.accent2
        case .live:  Theme.live
        default:     Theme.accentBronze
        }
    }
}

/// Small live indicator: opacity pulses 1 ↔ 0.3 forever (mockup `.livedot`).
/// Sits inline beside the subtitle, so it carries no top padding and lets the
/// enclosing HStack center it against the subtitle text.
private struct PulsingLiveDot: View {
    @State private var dim = false
    var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.3 : 1)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                       value: dim)
            .onAppear { dim = true }
            .accessibilityLabel("running")
    }
}
