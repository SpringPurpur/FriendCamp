import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self)             private var auth
    @Environment(GroupService.self)            private var groupService
    @Environment(GroupDataStore.self)          private var dataStore
    @Environment(UserPreferencesService.self)  private var prefs
    @Environment(MapVisibilityPreferences.self) private var mapVisibility
    @Environment(ThemePreferences.self) private var theme

    @State private var showAddGroupSheet = false
    @State private var selectedMemberForDetail: GroupMember?

    // Roster-ul rămâne scopat la grupul ACTIV — reprezintă "membrii acestui grup",
    // spre deosebire de dataStore.members, care combină toate grupurile vizibile pe hartă.
    private var activeGroupMembers: [GroupMember] {
        guard let activeId = groupService.activeGroupId else { return [] }
        return dataStore.members.filter { $0.groupId == activeId }
    }

    // Căutat în roster-ul grupului ACTIV, nu în dataStore.members brut — altfel, într-o
    // listă multi-grup, primul rând găsit ar putea reflecta rolul dintr-un alt grup decât
    // cel activ (isAdmin ar arăta greșit dacă ești admin într-un grup și membru în altul).
    private var currentUser: GroupMember? {
        guard let uid = auth.currentUserId else { return nil }
        return activeGroupMembers.first { $0.id == uid }
    }

    var body: some View {
        NavigationStack {
            List {
                if let currentUser {
                    Section {
                        UserHeaderCard(user: currentUser)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    ForEach(groupService.myGroups) { membership in
                        MyGroupRow(
                            membership: membership,
                            isActive: membership.groupId == groupService.activeGroupId,
                            isVisibleOnMap: mapVisibility.isVisible(membership.groupId),
                            onSetActive: { groupService.setActiveGroup(membership.groupId) },
                            onToggleVisible: { mapVisibility.setVisible(membership.groupId, $0) }
                        )
                    }
                    Button {
                        showAddGroupSheet = true
                    } label: {
                        Label("Alătură-te sau creează alt grup", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Grupurile mele")
                }

                Section {
                    ForEach(activeGroupMembers) { member in
                        MemberListRow(
                            member: member,
                            isCurrentUser: member.id == auth.currentUserId,
                            onTap: { selectedMemberForDetail = member }
                        )
                    }
                } header: {
                    Text("Membrii (\(activeGroupMembers.count))")
                }

                Section {
                    StatRow(icon: "mappin.circle.fill", color: .orange,
                            label: "Puncte marcate", value: "\(dataStore.pois.count)")
                    StatRow(icon: "doc.text.fill", color: .blue,
                            label: "Postări blog", value: "\(dataStore.posts.count)")
                    StatRow(icon: "creditcard.fill", color: .purple,
                            label: "Cheltuieli înregistrate", value: "\(dataStore.expenses.count)")
                } header: {
                    Text("Statistici trip")
                }

                Section {
                    NavigationLink(destination: AppearanceSettingsView(theme: theme)) {
                        Label("Aspect", systemImage: "paintbrush.fill")
                            .labelStyle(ColoredIconLabelStyle(color: .purple))
                    }
                    NavigationLink(destination: PrivacySettingsView(prefsService: prefs)) {
                        Label("Confidențialitate", systemImage: "hand.raised.fill")
                            .labelStyle(ColoredIconLabelStyle(color: .blue))
                    }
                    Button {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Deconectare", systemImage: "rectangle.portrait.and.arrow.right")
                            .labelStyle(ColoredIconLabelStyle(color: .gray))
                    }
                } header: {
                    Text("Cont")
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showAddGroupSheet) {
                GroupOnboardingView(isPresentedAsSheet: true)
            }
            .sheet(item: $selectedMemberForDetail) { member in
                MemberDetailSheet(member: member)
            }
        }
    }
}

// MARK: - Sub-views

struct UserHeaderCard: View {
    let user: GroupMember

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(user.avatarColor.gradient)
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(radius: 6)
                .overlay {
                    Text(user.initials)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.title2.bold())
                    if user.isAdmin {
                        Image(systemName: "crown.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                    }
                }
                Text("Eu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct MyGroupRow: View {
    let membership: MyGroupMembership
    let isActive: Bool
    let isVisibleOnMap: Bool
    let onSetActive: () -> Void
    let onToggleVisible: (Bool) -> Void

    @State private var codeCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onSetActive) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? .green : .secondary)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Text(membership.group.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                    if membership.role == "admin" {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = membership.group.inviteCode
                    codeCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { codeCopied = false }
                } label: {
                    HStack(spacing: 4) {
                        Text(membership.group.inviteCode)
                            .font(.caption.monospaced())
                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .foregroundStyle(codeCopied ? .green : Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Toggle("Vizibil pe hartă", isOn: Binding(
                get: { isVisibleOnMap },
                set: onToggleVisible
            ))
            .font(.caption)
            .tint(.green)
        }
        .padding(.vertical, 4)
    }
}

struct MemberListRow: View {
    let member: GroupMember
    let isCurrentUser: Bool
    var onTap: () -> Void = {}

    @Environment(GroupService.self)   private var groupService
    @Environment(GroupDataStore.self) private var dataStore

    @State private var showTransferConfirm = false
    @State private var isTransferring = false

    // Doar adminul curent poate promova pe altcineva, și doar dacă acela nu e deja admin.
    // Rolul se verifică pentru grupul ACTIV — member.groupId e mereu grupul activ aici,
    // deoarece MemberListRow e folosit doar din lista deja filtrată pe activeGroupMembers.
    private var canPromote: Bool {
        groupService.activeUserRole == "admin" && !isCurrentUser && !member.isAdmin
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(member.avatarColor.gradient)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(member.initials)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isCurrentUser ? "\(member.name) (tu)" : member.name)
                        .font(.subheadline)
                        .fontWeight(isCurrentUser ? .bold : .regular)
                    if member.isAdmin {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(member.isOnline ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(member.isOnline ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: member.batteryIcon)
                    .font(.caption)
                    .foregroundStyle(member.battery > 20 ? Color.green : Color.red)
                Text("\(member.battery)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canPromote {
                Button {
                    showTransferConfirm = true
                } label: {
                    Image(systemName: "crown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isTransferring)
                .padding(.leading, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .confirmationDialog(
            "Faci pe \(member.name) admin?",
            isPresented: $showTransferConfirm,
            titleVisibility: .visible
        ) {
            Button("Fă admin", role: .destructive) {
                Task { await promote() }
            }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Tu rămâi membru obișnuit — un singur admin poate exista per grup.")
        }
    }

    private func promote() async {
        isTransferring = true
        let groupId = member.groupId
        let success = await groupService.transferAdmin(groupId: groupId, to: member.id)
        if success {
            await dataStore.refreshMembersAndPOIs()
        }
        isTransferring = false
    }
}

struct StatRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.primary)
                .labelStyle(ColoredIconLabelStyle(color: color))
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Custom Label Style

struct ColoredIconLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
            configuration.title
        }
    }
}
