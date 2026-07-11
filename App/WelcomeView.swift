import SwiftUI

struct WelcomeView: View {
    let newSession: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Fabled")
                .font(Theme.display)
                .foregroundStyle(Theme.bronze)
            Text("Native Claude Code for the Mac")
                .foregroundStyle(.secondary)
            Button("New Session…", action: newSession)
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
