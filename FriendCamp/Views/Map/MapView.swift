import SwiftUI
import MapKit
import Observation
import Supabase
import MapCache

// MARK: - ViewModel (UI state only — date reale vin din GroupDataStore)

@Observable
final class MapViewModel {
    var selectedMember: GroupMember?
    var selectedPOI: PointOfInterest?
    // Plasare POI: userul apasă +, apoi atinge harta pentru a alege poziția
    var isPlacingPOI = false
    var pendingPOICoordinate: CLLocationCoordinate2D?
}

// MARK: - Progres descărcare hartă offline

// RegionDownloaderDelegate e apelat de pe un DispatchQueue de fundal (nu Swift Concurrency) —
// sărim explicit pe main thread înainte să mutăm proprietăți @Observable.
@Observable
final class OfflineDownloadState: NSObject, RegionDownloaderDelegate {
    var progress: Double = 0
    var isDownloading = false

    func regionDownloader(_ regionDownloader: RegionDownloader, didDownloadPercentage percentage: Double) {
        DispatchQueue.main.async { self.progress = percentage / 100 }
    }

    func regionDownloader(_ regionDownloader: RegionDownloader, didFinishDownload tilesDownloaded: TileNumber) {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.progress = 1
        }
    }
}

// MARK: - MapView

struct MapView: View {
    @Environment(GroupDataStore.self) private var dataStore
    @Environment(GroupService.self)   private var groupService
    @Environment(AuthService.self)    private var auth
    @Environment(UserPreferencesService.self) private var prefs
    @Environment(MapVisibilityPreferences.self) private var mapVisibility
    @Environment(TabRouter.self) private var tabRouter

    @State private var vm = MapViewModel()
    @State private var locationService = LocationService()
    @State private var networkMonitor = NetworkMonitor()
    @State private var hasCenteredOnUser = false
    // Sursa de tile-uri urmează conectivitatea DOAR o dată, la deschiderea hărții — după
    // aceea userul comută liber din meniu, fără să fie suprascris la schimbări de rețea.
    @State private var tileSource: MapTileSource = .apple
    @State private var hasSetInitialTileSource = false
    // Urmărit continuu cât timp harta e vizibilă, ca la activarea modului de plasare
    // să existe deja o coordonată validă fără să aștepte primul eveniment de cameră.
    @State private var mapCenterCoordinate = CLLocationCoordinate2D(latitude: 45.9440, longitude: 24.9675)
    @State private var lastKnownRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.9440, longitude: 24.9675),
        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
    )
    // Setat de MapKitMapView pentru a centra o singură dată — MapKitMapView îl resetează
    // la nil imediat după ce aplică centrarea.
    @State private var centerRequest: CLLocationCoordinate2D?

    // Instanță unică, ținută aici (nu în MapKitMapView, care e reconstruit la fiecare
    // redraw) — atât randarea cât și descărcarea explicită de regiune scriu în același cache.
    @State private var mapCache = MapCache(withConfig: {
        var config = MapCacheConfig()
        config.capacity = 300 * 1024 * 1024
        return config
    }())
    @State private var offlineDownload = OfflineDownloadState()
    @State private var pendingDownloader: RegionDownloader?
    @State private var showDownloadConfirm = false

    // Grupurile arătate pe hartă — folosite pentru poll/realtime, ca să nu se mai facă
    // query pentru grupurile pe care userul le-a ascuns explicit din Profil.
    private var visibleGroupIds: Set<UUID> {
        Set(groupService.myGroups.map(\.groupId).filter(mapVisibility.isVisible))
    }
    // Heartbeat-ul merge către TOATE grupurile, indiferent de vizibilitate — toggle-ul e
    // local/cosmetic ("ce văd eu"), nu ar trebui să te facă invizibil colegilor din acel grup.
    private var allGroupIds: Set<UUID> {
        Set(groupService.myGroups.map(\.groupId))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapKitMapView(
                    members: dataStore.members,
                    pois: dataStore.pois,
                    isMultiGroup: groupService.myGroups.count > 1,
                    mapCache: mapCache,
                    tileSource: tileSource,
                    centerRequest: $centerRequest,
                    onSelectMember: { vm.selectedMember = $0 },
                    onSelectPOI: { vm.selectedPOI = $0 },
                    onRegionChange: { region in
                        mapCenterCoordinate = region.center
                        lastKnownRegion = region
                    }
                )
                .ignoresSafeArea(edges: .top)
                .onAppear {
                    locationService.requestPermission()
                    // Dacă LocationService a pornit deja cu o poziție din cache (userul a mai
                    // acordat permisiunea în trecut), .onChange de mai jos nu se declanșează
                    // niciodată — hasLocation e true încă de la primul render, nu doar "devine" true.
                    centerOnUserIfNeeded()
                    if !hasSetInitialTileSource {
                        hasSetInitialTileSource = true
                        tileSource = networkMonitor.isConnected ? .apple : .openStreetMap
                    }
                }
                .onChange(of: locationService.hasLocation) { _, _ in
                    centerOnUserIfNeeded()
                }
                .onChange(of: locationService.userLocation) { _, _ in
                    Task { await uploadHeartbeat() }
                }
                .onChange(of: tabRouter.pendingMapCenter) { _, newValue in
                    guard let newValue else { return }
                    centerRequest = newValue
                    tabRouter.pendingMapCenter = nil
                }

                if tileSource == .openStreetMap {
                    // Atribuire obligatorie conform politicii OpenStreetMap pentru tile-uri gratuite.
                    Text("© OpenStreetMap contributors")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 70)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                if offlineDownload.isDownloading {
                    VStack(spacing: 4) {
                        ProgressView(value: offlineDownload.progress)
                        Text("Descărcare hartă offline… \(Int(offlineDownload.progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                if vm.isPlacingPOI {
                    Image(systemName: PointOfInterest.pinIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(PointOfInterest.defaultPinColor)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: -20)

                    PlacingPOIConfirmBar(
                        onCancel: { vm.isPlacingPOI = false },
                        onConfirm: {
                            vm.pendingPOICoordinate = mapCenterCoordinate
                            vm.isPlacingPOI = false
                        }
                    )
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    MemberStatusBar(members: dataStore.members, groupService: groupService) { member in
                        vm.selectedMember = member
                    }
                }
            }
            .navigationTitle("FriendCamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        centerOnUser()
                    } label: {
                        Image(systemName: locationService.hasLocation
                              ? "location.fill" : "location.slash")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section("Sursă hartă") {
                            Button {
                                tileSource = .apple
                            } label: {
                                if tileSource == .apple {
                                    Label("Apple Maps", systemImage: "checkmark")
                                } else {
                                    Text("Apple Maps")
                                }
                            }
                            Button {
                                tileSource = .openStreetMap
                            } label: {
                                if tileSource == .openStreetMap {
                                    Label("OpenStreetMap", systemImage: "checkmark")
                                } else {
                                    Text("OpenStreetMap")
                                }
                            }
                        }
                        Button {
                            // Descărcarea are sens doar cu overlay-ul OSM activ.
                            tileSource = .openStreetMap
                            prepareDownload()
                        } label: {
                            Label("Descarcă zona vizibilă pentru offline", systemImage: "arrow.down.circle")
                        }
                        .disabled(offlineDownload.isDownloading)
                    } label: {
                        Image(systemName: "map")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.isPlacingPOI.toggle()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(vm.isPlacingPOI ? Color.orange : Color.accentColor)
                    }
                }
            }
            .confirmationDialog(
                "Descarcă zona vizibilă pentru offline?",
                isPresented: $showDownloadConfirm,
                titleVisibility: .visible
            ) {
                Button("Descarcă") { startDownload() }
                Button("Anulează", role: .cancel) { pendingDownloader = nil }
            } message: {
                if let pendingDownloader {
                    Text("Aproximativ \(ByteCountFormatter.string(fromByteCount: Int64(pendingDownloader.estimateRegionByteSize()), countStyle: .file)) — rămâne disponibilă offline pe acest telefon.")
                }
            }
        }
        // Polling membri la fiecare 15s — fallback dacă Realtime pică (reconectare, background)
        .task(id: visibleGroupIds) {
            await dataStore.pollMembers(groupIds: Array(visibleGroupIds))
        }
        // Realtime — actualizează membrii aproape instant la orice update de locație
        .task(id: visibleGroupIds) {
            await dataStore.subscribeToLocationUpdates(groupIds: Array(visibleGroupIds))
        }
        // Heartbeat: retrimite locația + bateria la fiecare 20s, chiar dacă userul stă pe loc,
        // altfel is_online/bateria rămân înghețate la ultima valoare din momentul primului fix GPS.
        // Merge la toate grupurile (nu doar cele vizibile pe hartă), vezi allGroupIds mai sus.
        .task(id: allGroupIds) {
            while !Task.isCancelled {
                await uploadHeartbeat()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        .sheet(item: $vm.selectedMember) { member in
            MemberDetailSheet(member: member)
        }
        .sheet(item: $vm.selectedPOI) { poi in
            POIDetailSheet(poi: poi)
        }
        .sheet(isPresented: Binding(
            get: { vm.pendingPOICoordinate != nil },
            set: { if !$0 { vm.pendingPOICoordinate = nil } }
        )) {
            if let coordinate = vm.pendingPOICoordinate {
                POICreateSheet(coordinate: coordinate) { vm.pendingPOICoordinate = nil }
            }
        }
    }

    private func centerOnUser() {
        guard let coord = locationService.userLocation else { return }
        // MapKitMapView aplică setRegion(animated: true) și păstrează span-ul curent al hărții.
        centerRequest = coord
    }

    // Centrează o singură dată, automat, la deschiderea hărții — apoi userul rămâne liber
    // să navigheze fără să fie re-centrat la fiecare update de poziție.
    private func centerOnUserIfNeeded() {
        guard !hasCenteredOnUser, locationService.userLocation != nil else { return }
        hasCenteredOnUser = true
        centerOnUser()
    }

    // Zoom 13...17 acoperă o zonă de câțiva km — suficient pentru o zonă de camping fixă,
    // fără să încerce să descarce tot globul dacă userul a dat zoom out prea mult.
    private var downloadTileRegion: TileCoordsRegion? {
        let region = lastKnownRegion
        return TileCoordsRegion(
            topLeftLatitude: region.center.latitude + region.span.latitudeDelta / 2,
            topLeftLongitude: region.center.longitude - region.span.longitudeDelta / 2,
            bottomRightLatitude: region.center.latitude - region.span.latitudeDelta / 2,
            bottomRightLongitude: region.center.longitude + region.span.longitudeDelta / 2,
            minZoom: 13,
            maxZoom: 17
        )
    }

    private func prepareDownload() {
        guard let region = downloadTileRegion else { return }
        let downloader = RegionDownloader(forRegion: region, mapCache: mapCache)
        downloader.delegate = offlineDownload
        pendingDownloader = downloader
        showDownloadConfirm = true
    }

    private func startDownload() {
        guard let downloader = pendingDownloader else { return }
        offlineDownload.isDownloading = true
        offlineDownload.progress = 0
        downloader.start()
    }

    private func uploadHeartbeat() async {
        guard let coord = locationService.userLocation,
              prefs.preferences.shareLocation,
              let userId = auth.currentUserId else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel
        let batteryPct = battery >= 0 ? Int(battery * 100) : nil
        for membership in groupService.myGroups {
            await dataStore.uploadLocation(userId: userId, groupId: membership.groupId,
                                            coordinate: coord, batteryPercent: batteryPct)
        }
    }
}

// MARK: - Map Pins

struct MemberMapPin: View {
    let member: GroupMember
    var ringColor: Color = .white

    var body: some View {
        ZStack {
            Circle()
                .fill(member.avatarColor.gradient)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(ringColor, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Text(member.initials)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(member.isOnline ? Color.green : Color.gray)
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }
}

struct POIMapPin: View {
    let poi: PointOfInterest

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.systemBackground))
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Image(systemName: PointOfInterest.pinIcon)
                .font(.system(size: 17))
                .foregroundStyle(poi.displayColor)
        }
    }
}

struct PlacingPOIConfirmBar: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Anulează", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
            Button("Confirmă", action: onConfirm)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Member Status Bar

struct MemberStatusBar: View {
    let members: [GroupMember]
    let groupService: GroupService
    let onTap: (GroupMember) -> Void

    private var isMultiGroup: Bool { groupService.myGroups.count > 1 }

    private func groupName(for groupId: UUID) -> String? {
        guard isMultiGroup else { return nil }
        return groupService.myGroups.first { $0.groupId == groupId }?.group.name
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(members) { member in
                    MemberChip(
                        member: member,
                        ringColor: isMultiGroup ? member.groupId.groupAccentColor : .white,
                        groupName: groupName(for: member.groupId)
                    )
                    .onTapGesture { onTap(member) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}

struct MemberChip: View {
    let member: GroupMember
    var ringColor: Color = .white
    var groupName: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(member.avatarColor.gradient)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(ringColor, lineWidth: 2))
                .overlay {
                    Text(member.initials)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(member.isOnline ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(member.isOnline ? "Live" : timeAgo(member.lastSeen))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let groupName {
                        Text("· \(groupName)")
                            .font(.caption2)
                            .foregroundStyle(ringColor)
                    }
                }
            }

            HStack(spacing: 2) {
                Image(systemName: member.batteryIcon)
                    .font(.caption2)
                    .foregroundStyle(member.battery > 20 ? Color.green : Color.red)
                Text("\(member.battery)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }
}

// MARK: - Detail Sheets

struct MemberDetailSheet: View {
    let member: GroupMember
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupService.self)   private var groupService
    @Environment(GroupDataStore.self) private var dataStore
    @Environment(TabRouter.self)      private var tabRouter

    @State private var selectedPOI: PointOfInterest?
    @State private var selectedPost: BlogPost?

    private var isMultiGroup: Bool { groupService.myGroups.count > 1 }
    private var ringColor: Color { isMultiGroup ? member.groupId.groupAccentColor : .white }
    private var groupName: String? {
        guard isMultiGroup else { return nil }
        return groupService.myGroups.first { $0.groupId == member.groupId }?.group.name
    }

    // POI-urile sunt multi-grup pe hartă, deci filtrarea e mereu validă indiferent de grupul
    // membrului. Postările/cheltuielile rămân scopate la grupul ACTIV — dacă membrul e din alt
    // grup, acele liste nici nu conțin datele lui, deci un "0" ar fi înșelător; le ascundem.
    private var memberPOIs: [PointOfInterest] {
        dataStore.pois.filter { $0.createdById == member.id }
    }
    private var isInActiveGroup: Bool { member.groupId == groupService.activeGroupId }
    private var memberPosts: [BlogPost] {
        dataStore.posts.filter { $0.author.id == member.id }
    }
    private var memberExpensesCount: Int {
        dataStore.expenses.filter { $0.paidBy.id == member.id }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Circle()
                            .fill(member.avatarColor.gradient)
                            .frame(width: 88, height: 88)
                            .overlay(Circle().stroke(ringColor, lineWidth: 3))
                            .shadow(radius: 8)
                            .overlay {
                                Text(member.initials)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Text(member.name)
                                    .font(.title.bold())
                                if member.isAdmin {
                                    Image(systemName: "crown.fill")
                                        .font(.title3)
                                        .foregroundStyle(.yellow)
                                }
                            }
                            if let groupName {
                                Text(groupName)
                                    .font(.caption.bold())
                                    .foregroundStyle(ringColor)
                            }
                        }

                        HStack(spacing: 32) {
                            DetailStat(
                                icon: "circle.fill",
                                iconColor: member.isOnline ? .green : .gray,
                                label: member.isOnline ? "Online" : "Offline",
                                value: member.isOnline ? "Live" : timeAgo(member.lastSeen)
                            )
                            DetailStat(
                                icon: member.batteryIcon,
                                iconColor: member.battery > 20 ? .green : .red,
                                label: "Baterie",
                                value: "\(member.battery)%"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    Button {
                        tabRouter.goToMap(centeredOn: member.coordinate)
                        dismiss()
                    } label: {
                        Label("Vezi pe hartă", systemImage: "location.fill")
                    }
                }

                Section {
                    StatRow(icon: "mappin.circle.fill", color: .orange,
                            label: "Puncte marcate", value: "\(memberPOIs.count)")
                    if isInActiveGroup {
                        StatRow(icon: "doc.text.fill", color: .blue,
                                label: "Postări blog", value: "\(memberPosts.count)")
                        StatRow(icon: "creditcard.fill", color: .purple,
                                label: "Cheltuieli plătite", value: "\(memberExpensesCount)")
                    }
                } header: {
                    Text("Statistici")
                }

                if !memberPOIs.isEmpty {
                    Section {
                        ForEach(memberPOIs) { poi in
                            Button {
                                selectedPOI = poi
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: PointOfInterest.pinIcon)
                                        .foregroundStyle(poi.displayColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(poi.title)
                                            .foregroundStyle(.primary)
                                        Text(poi.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Puncte de interes plasate (\(memberPOIs.count))")
                    }
                }

                // Postările, ca și statisticile de mai sus, sunt scopate la grupul ACTIV.
                if isInActiveGroup, !memberPosts.isEmpty {
                    Section {
                        ForEach(memberPosts) { post in
                            Button {
                                selectedPost = post
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(post.title)
                                            .foregroundStyle(.primary)
                                        Text(post.date, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Postări blog (\(memberPosts.count))")
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Închide") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedPOI) { poi in
            POIDetailSheet(poi: poi)
        }
        .sheet(item: $selectedPost) { post in
            NavigationStack {
                BlogPostDetailView(post: post)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Închide") { selectedPost = nil }
                        }
                    }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        return minutes < 60 ? "acum \(minutes)m" : "acum \(minutes / 60)h"
    }
}

struct POIDetailSheet: View {
    let poi: PointOfInterest
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupDataStore.self) private var dataStore
    @Environment(GroupService.self)   private var groupService
    @Environment(AuthService.self)    private var auth

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showFullscreenPhoto = false
    @State private var isDeleting = false

    // Rolul se verifică pentru grupul PROPRIU al POI-ului, nu un rol global — un user poate
    // fi admin într-un grup vizibil pe hartă și membru simplu în altul.
    private var canManage: Bool {
        poi.createdById == auth.currentUserId ||
            groupService.myGroups.first { $0.groupId == poi.groupId }?.role == "admin"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: PointOfInterest.pinIcon)
                        .font(.title2)
                        .foregroundStyle(poi.displayColor)
                        .frame(width: 44, height: 44)
                        .background(poi.displayColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(poi.title)
                            .font(.headline)
                    }
                }

                if let photoURL = poi.photoURL {
                    AsyncImage(url: photoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.15)
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { showFullscreenPhoto = true }
                    .fullScreenCover(isPresented: $showFullscreenPhoto) {
                        FullScreenImageViewer(url: photoURL)
                    }
                }

                Divider()

                Text(poi.description)
                    .font(.body)
                    .foregroundStyle(.primary)

                HStack {
                    Image(systemName: "person.circle")
                        .foregroundStyle(.secondary)
                    Text("Adăugat de \(poi.createdBy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(poi.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("")
            .toolbar {
                if canManage {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Editează", systemImage: "pencil") { showEditSheet = true }
                            Button("Șterge", systemImage: "trash", role: .destructive) {
                                showDeleteConfirm = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Închide") { dismiss() }
                }
            }
            .confirmationDialog("Ștergi acest punct?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Șterge", role: .destructive) { Task { await deletePOI() } }
                Button("Anulează", role: .cancel) {}
            }
            .sheet(isPresented: $showEditSheet) {
                POICreateSheet(editing: poi) {
                    showEditSheet = false
                    dismiss()
                }
            }
            .disabled(isDeleting)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func deletePOI() async {
        let groupId = poi.groupId
        isDeleting = true
        if poi.photoURL != nil {
            let path = "\(groupId.uuidString)/\(poi.id.uuidString).jpg"
            _ = try? await supabase.storage.from("poi-photos").remove(paths: [path])
        }
        _ = try? await supabase.from("points_of_interest")
            .delete()
            .eq("id", value: poi.id.uuidString)
            .execute()
        await dataStore.refreshMembersAndPOIs()
        dismiss()
    }
}

// MARK: - Helpers

struct DetailStat: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }
}
