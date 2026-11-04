import SwiftUI

struct StatusMessageView: View {
    let message: String
    let isError: Bool
    let validationID: UUID?

    @State private var highlighted = false
    @State private var resultHeight: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                result
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        resultHeight = height
                    }
            }
            .defaultScrollAnchor(.top)
            .id(message)
            .frame(height: min(resultHeight, 110))
        }
        .background(Color.accentColor.opacity(highlighted ? 0.16 : 0))
        .task(id: validationID) {
            highlighted = validationID != nil
            guard highlighted else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) {
                highlighted = false
            }
        }
    }

    private var result: some View {
        Label(message, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.callout)
            .foregroundStyle(isError ? Color.red : Color.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}
