import SwiftUI

/// The locked chip label — the shared chrome behind the composer's chips
/// (project, model, effort, permission). A `Menu`'s `label:`, so it carries no
/// menu wrapper of its own: callers add `.menuStyle`/`.menuIndicator`/`.fixedSize`.
/// `textColor` is the only per-chip variable (the model chip reads in bronze,
/// the rest in ink); the leading icon is always bronze and the caret always faint.
struct ChipLabel: View {
    let icon: String
    let label: String
    var textColor: Color = Theme.ink

    var body: some View {
        HStack(spacing: Theme.spaceXS) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accentBronze)
            Text(label)
                .foregroundStyle(textColor)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .font(.system(size: 12))
        .padding(.horizontal, Theme.spaceS)
        .padding(.vertical, Theme.spaceXS + 1)
        .background(Theme.panelRecessed, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}
