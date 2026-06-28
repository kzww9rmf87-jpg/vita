import SwiftUI

@main
struct VitaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    if appState.onboardingComplete {
                        MainTabView()
                    } else {
                        ConversationalOnboardingView()
                            .onReceive(NotificationCenter.default.publisher(for: .vitaOnboardingComplete)) { _ in
                                appState.onboardingComplete = true
                            }
                    }
                } else {
                    AuthView()
                }
            }
            .task {
                await appState.bootstrap()
            }
        }
    }
}

// MARK: — Navigation principale

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }

            DashboardView()
                .tabItem {
                    Label("Tendances", systemImage: "chart.line.uptrend.xyaxis")
                }

            ChatView()
                .tabItem {
                    Label("VITA", systemImage: "brain.head.profile")
                }

            ReportsView()
                .tabItem {
                    Label("Bilans", systemImage: "doc.text.fill")
                }

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: "person.fill")
                }
        }
        .tint(VitaColor.accent)
    }
}

// MARK: — État global de l'app

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var onboardingComplete = false
    @Published var isLoading = true

    func bootstrap() async {
        defer { isLoading = false }

        // Charger les tokens depuis le Keychain
        if let token = KeychainHelper.read("vita.access_token") {
            await APIClient.shared.setTokens(
                access: token,
                refresh: KeychainHelper.read("vita.refresh_token") ?? ""
            )
            isAuthenticated = true
            onboardingComplete = UserDefaults.standard.bool(forKey: "vita.onboarding.complete")

            // Synchroniser Apple Health en arrière-plan
            Task {
                try? await HealthKitManager.shared.syncToday()
            }
        }
    }
}

// MARK: — Vues placeholder (seront complétées en V1)

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            Text("Tendances — À venir")
                .navigationTitle("Tendances")
        }
    }
}

struct ReportsView: View {
    var body: some View {
        NavigationStack {
            Text("Bilans — À venir")
                .navigationTitle("Bilans")
        }
    }
}

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            Text("Profil — À venir")
                .navigationTitle("Profil")
        }
    }
}

struct DailyRecommendationView: View {
    let recommendation: DailyRecommendation?

    var body: some View {
        NavigationStack {
            ZStack {
                VitaColor.background.ignoresSafeArea()
                if let reco = recommendation {
                    VStack(spacing: VitaSpacing.xl) {
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(VitaColor.accent)
                        Text(reco.content)
                            .font(VitaFont.headline(20))
                            .foregroundColor(VitaColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, VitaSpacing.xl)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Ta journée")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
