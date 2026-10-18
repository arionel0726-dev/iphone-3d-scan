import SwiftUI

/// Sign-in only — no self-registration. Managers are invited out-of-band
/// via the existing `bun run auth:create-user` script in the 2-3d-store
/// backend; this screen uses those same credentials against the existing
/// Better Auth email/password endpoint. There is no separate auth system.
struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Вход менеджера")
                            .font(.largeTitle.bold())
                        Text("Самостоятельная регистрация недоступна. Используйте аккаунт, выданный администратором магазина.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField("Электронная почта", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Войти").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await appState.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView().environmentObject(AppState())
}
