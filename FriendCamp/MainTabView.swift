import SwiftUI

struct MainTabView: View {
    @Environment(TabRouter.self) private var tabRouter

    var body: some View {
        TabView(selection: Binding(
            get: { tabRouter.selectedTab },
            set: { tabRouter.selectedTab = $0 }
        )) {
            MapView()
                .tabItem { Label("Hartă", systemImage: "map.fill") }
                .tag(AppTab.map)

            BlogView()
                .tabItem { Label("Blog", systemImage: "doc.text.fill") }
                .tag(AppTab.blog)

            ExpensesView()
                .tabItem { Label("Cheltuieli", systemImage: "creditcard.fill") }
                .tag(AppTab.expenses)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
    }
}