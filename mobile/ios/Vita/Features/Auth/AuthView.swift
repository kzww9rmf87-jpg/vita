import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        ZStack {
            VitaColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: VitaSpacing.sm) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(VitaColor.accent)
                    Text("VITA")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(VitaColor.textPrimary)
                    Text("Ton coach de vie intelligent")
                        .font(VitaFont.body())
                        .foregroundColor(VitaColor.textSecondary)
                }

                Spacer()

                VStack(spacing: VitaSpacing.sm) {
                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await vm.handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))

                    // Divider
                    HStack {
                        Rectangle().fill(VitaColor.neutral.opacity(0.3)).frame(height: 1)
                        Text("ou").font(VitaFont.caption()).foregroundColor(VitaColor.textTertiary)
                        Rectangle().fill(VitaColor.neutral.opacity(0.3)).frame(height: 1)
                    }

                    // Email
                    VStack(spacing: VitaSpacing.sm) {
                        TextField("Email", text: $vm.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding(VitaSpacing.md)
                            .background(VitaColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))

                        SecureField("Mot de passe", text: $vm.password)
                            .textContentType(vm.isRegistering ? .newPassword : .password)
                            .padding(VitaSpacing.md)
                            .background(VitaColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))

                        if vm.isRegistering {
                            TextField("Prénom", text: $vm.firstName)
                                .textContentType(.givenName)
                                .padding(VitaSpacing.md)
                                .background(VitaColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
                        }
                    }

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(VitaFont.caption())
                            .foregroundColor(VitaColor.warning)
                            .multilineTextAlignment(.center)
                    }

                    Button(vm.isRegistering ? "Créer mon compte" : "Se connecter") {
                        Task { await vm.submitEmailAuth() }
                    }
                    .buttonStyle(VitaPrimaryButtonStyle())
                    .disabled(vm.isLoading)

                    Button(vm.isRegistering ? "Déjà un compte ? Se connecter" : "Créer un compte") {
                        withAnimation(.vitaFast) { vm.isRegistering.toggle() }
                    }
                    .font(VitaFont.body())
                    .foregroundColor(VitaColor.textSecondary)
                }
                .padding(.horizontal, VitaSpacing.lg)
                .padding(.bottom, VitaSpacing.xxl)
            }
        }
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var firstName = ""
    @Published var isRegistering = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func submitEmailAuth() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let tokens: TokenResponse
            if isRegistering {
                struct RegisterBody: Encodable { let email, password, firstName: String }
                tokens = try await APIClient.shared.post("/auth/register", body: RegisterBody(
                    email: email, password: password, firstName: firstName
                ))
            } else {
                struct LoginBody: Encodable { let email, password: String }
                tokens = try await APIClient.shared.post("/auth/login", body: LoginBody(
                    email: email, password: password
                ))
            }
            await APIClient.shared.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            NotificationCenter.default.post(name: .vitaAuthComplete, object: nil)
        } catch APIError.conflict {
            errorMessage = "Cette adresse email est déjà utilisée."
        } catch APIError.unauthorized {
            errorMessage = "Email ou mot de passe incorrect."
        } catch {
            errorMessage = "Une erreur est survenue. Réessaie."
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else { return }

            struct AppleBody: Encodable { let identityToken: String; let firstName: String? }
            do {
                let tokens: TokenResponse = try await APIClient.shared.post(
                    "/auth/apple",
                    body: AppleBody(
                        identityToken: token,
                        firstName: credential.fullName?.givenName
                    )
                )
                await APIClient.shared.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
                NotificationCenter.default.post(name: .vitaAuthComplete, object: nil)
            } catch {
                errorMessage = "Connexion Apple échouée."
            }
        case .failure:
            break
        }
    }
}

extension Notification.Name {
    static let vitaAuthComplete = Notification.Name("vita.auth.complete")
}
