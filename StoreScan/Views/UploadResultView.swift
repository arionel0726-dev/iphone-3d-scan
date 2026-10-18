import SwiftUI

/// Final confirmation after a successful upload, with a link to open the
/// web review screen (/scans/:id) added in stage C of the web app — the
/// scan stays a draft there until a manager applies it; this app's job
/// ends at a successful upload.
struct UploadResultView: View {
    @EnvironmentObject private var appState: AppState
    let outcome: UploadOutcome

    var body: some View {
        VStack(spacing: 20) {
            switch outcome {
            case let .success(scanId, reviewURLBase):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Скан отправлен").font(.title2.bold())
                Text("Он появится как черновик в веб-приложении — планировка не изменится, пока менеджер не проверит и не применит скан.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let reviewURL = URL(string: "/scans/\(scanId.uuidString)", relativeTo: reviewURLBase) {
                    Link(destination: reviewURL) {
                        Label("Открыть проверку скана", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    ShareLink(item: reviewURL) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

            case let .failure(message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Не удалось отправить скан").font(.title2.bold())
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            Button("К списку магазинов") { appState.returnToStorePicker() }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    UploadResultView(outcome: .success(scanId: UUID(), reviewURLBase: URL(string: "http://localhost:3000")!))
        .environmentObject(AppState())
}
