import SwiftUI

@main
struct FriendCampApp: App {
    @State private var auth          = AuthService()
    @State private var groupService  = GroupService()
    @State private var dataStore     = GroupDataStore()
    @State private var prefs         = UserPreferencesService()
    @State private var mapVisibility = MapVisibilityPreferences()
    @State private var theme         = ThemePreferences()
    @State private var tabRouter     = TabRouter()

    // Grupurile ale căror membri/POI-uri se încarcă — vizibile pe hartă, plus grupul activ
    // e mereu inclus implicit prin faptul că orice grup nou devine activ și vizibil.
    // Set, nu Array — .task(id:) nu retrigger-uiește la simpla reordonare a myGroups.
    private var visibleGroupIdsKey: Set<UUID> {
        Set(groupService.myGroups.map(\.groupId).filter(mapVisibility.isVisible))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.hasCheckedSession {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !auth.isAuthenticated {
                    AuthView()
                } else if !groupService.hasChecked {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groupService.myGroups.isEmpty {
                    GroupOnboardingView()
                } else {
                    ContentView()
                }
            }
            .environment(auth)
            .environment(groupService)
            .environment(dataStore)
            .environment(prefs)
            .environment(mapVisibility)
            .environment(theme)
            .environment(tabRouter)
            // Aplicat la nivelul cel mai exterior — inclusiv AuthView/GroupOnboardingView,
            // nu doar ContentView, ca tema să se vadă și înainte de autentificare.
            .preferredColorScheme(theme.appearanceMode.colorScheme)
            .tint(theme.accentColor)
            .animation(.easeInOut(duration: 0.3), value: auth.isAuthenticated)
            .animation(.easeInOut(duration: 0.25), value: groupService.myGroups.isEmpty)
            // Link-ul din emailul de confirmare deschide aplicația direct (friendcamp://auth-callback)
            .onOpenURL { url in
                Task { await auth.handleAuthCallback(url: url) }
            }
            .overlay(alignment: .top) {
                if auth.justVerifiedEmail {
                    EmailConfirmedBanner()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { auth.justVerifiedEmail = false }
                        }
                }
            }
            .animation(.spring(duration: 0.4), value: auth.justVerifiedEmail)
            // Când userId se schimbă (login/logout), configurează serviciile
            .task(id: auth.currentUserId) {
                guard let userId = auth.currentUserId else {
                    groupService.reset()
                    dataStore.reset()
                    prefs.reset()
                    mapVisibility.reset()
                    return
                }
                prefs.configure(userId: userId)
                mapVisibility.configure(userId: userId)
                await groupService.loadMyGroups(userId: userId)
            }
            // Membri + POI-uri — multi-grup, urmăresc setul de grupuri vizibile pe hartă
            .task(id: visibleGroupIdsKey) {
                await dataStore.loadMembersAndPOIs(groupIds: Array(visibleGroupIdsKey))
            }
            // Blog + Cheltuieli — rămân legate de un singur grup activ
            .task(id: groupService.activeGroupId) {
                guard let groupId = groupService.activeGroupId else { return }
                await dataStore.loadActiveGroupContent(groupId: groupId)
            }
        }
    }
}

// MARK: - EmailConfirmedBanner

private struct EmailConfirmedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Email confirmat cu succes!")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6)
        .padding(.horizontal)
    }
}
