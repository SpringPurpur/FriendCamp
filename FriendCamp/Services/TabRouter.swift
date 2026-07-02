import CoreLocation
import Observation

enum AppTab: Hashable {
    case map, blog, expenses, profile
}

// Punte între taburi — ex: butonul "Vezi pe hartă" dintr-un sheet de membru, deschis din
// Profil, trebuie să comute pe tab-ul Hartă ȘI să centreze pe coordonata acelui membru.
@Observable
final class TabRouter {
    var selectedTab: AppTab = .map
    var pendingMapCenter: CLLocationCoordinate2D?

    func goToMap(centeredOn coordinate: CLLocationCoordinate2D) {
        pendingMapCenter = coordinate
        selectedTab = .map
    }
}
