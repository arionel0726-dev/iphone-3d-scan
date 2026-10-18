import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.screen {
            case .checkingSession:
                ProgressView("Проверка сессии…")
            case .login:
                LoginView()
            case .storePicker:
                StorePickerView()
            case let .scanning(store, targetLayout):
                NavigationStack {
                    ScanCaptureView(store: store, targetLayout: targetLayout)
                }
            case let .uploadResult(outcome):
                UploadResultView(outcome: outcome)
            }
        }
        .task { await appState.bootstrap() }
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
