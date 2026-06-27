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

                    #if DEBUG
                    DevLoginButton(vm: vm)
                    #endif
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

    // Les CodingKeys explicites empêchent JSONEncoder.vita (.convertToSnakeCase)
    // de transformer firstName → first_name. Le backend Zod attend du camelCase.
    private struct LoginBody: Encodable {
        let email: String
        let password: String
    }

    private struct RegisterBody: Encodable {
        let email: String
        let password: String
        let firstName: String
    }

    func submitEmailAuth() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let tokens: TokenResponse
            if isRegistering {
                tokens = try await APIClient.shared.post("/auth/register", body: RegisterBody(
                    email: email, password: password, firstName: firstName
                ))
            } else {
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

    #if DEBUG
    // Compte de test créé automatiquement à la première utilisation.
    // Jamais compilé en configuration Release.
    private static let devEmail    = "dev@vita.test"
    private static let devPassword = "VitaDev2024!"
    private static let devName     = "Dev"

    func devLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let tokens: TokenResponse = try await APIClient.shared.post(
                "/auth/login",
                body: LoginBody(email: Self.devEmail, password: Self.devPassword)
            )
            await APIClient.shared.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            NotificationCenter.default.post(name: .vitaAuthComplete, object: nil)
        } catch APIError.unauthorized {
            // L'utilisateur de test n'existe pas encore — on le crée puis on se reconnecte.
            do {
                let _: TokenResponse = try await APIClient.shared.post(
                    "/auth/register",
                    body: RegisterBody(email: Self.devEmail, password: Self.devPassword, firstName: Self.devName)
                )
                let tokens: TokenResponse = try await APIClient.shared.post(
                    "/auth/login",
                    body: LoginBody(email: Self.devEmail, password: Self.devPassword)
                )
                await APIClient.shared.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
                NotificationCenter.default.post(name: .vitaAuthComplete, object: nil)
            } catch {
                errorMessage = "Impossible de créer le compte de test : \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Connexion dev échouée : \(error.localizedDescription)"
        }
    }
    #endif

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

#if DEBUG
// Bouton visible uniquement en configuration Debug.
// Permet de tester VITA sur simulateur sans Sign in with Apple.
private struct DevLoginButton: View {
    @ObservedObject var vm: AuthViewModel

    var body: some View {
        Button {
            Task { await vm.devLogin() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                Text("Continuer en mode développeur")
            }
            .font(VitaFont.caption())
            .foregroundColor(VitaColor.textTertiary)
            .padding(.vertical, VitaSpacing.xs)
            .padding(.horizontal, VitaSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VitaRadius.sm)
                    .stroke(VitaColor.textTertiary.opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(vm.isLoading)
        .padding(.top, VitaSpacing.xs)
    }
}
#endif

extension Notification.Name {
    static let vitaAuthComplete = Notification.Name("vita.auth.complete")
}
