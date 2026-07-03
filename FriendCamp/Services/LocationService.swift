import CoreLocation
import Observation

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Observabil din MapView pentru a declanșa centrarea camerei la primul fix
    var hasLocation: Bool { userLocation != nil }

    private var hasRequestedAlwaysUpgrade = false
    private var hasRequestedFullAccuracy = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
        // manager.location oferă instant ultima poziție cunoscută din cache (dacă userul a mai
        // acordat permisiunea), fără să aștepte primul callback async de la startUpdatingLocation —
        // evită flash-ul regiunii hardcodate la redeschiderea aplicației.
        userLocation = manager.location?.coordinate
    }

    func requestPermission() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            configureForCurrentAuthorization()
        default:
            break
        }
    }

    func centerOnUser() {
        // Apelat din butonul "locate me" — refolosim ultima poziție cunoscută
        _ = userLocation
    }

    // Pornește actualizările și configurează tracking-ul de fundal/acuratețea completă
    // pentru orice nivel curent de autorizare — apelată atât după cererea inițială cât și
    // la fiecare schimbare de autorizare (upgrade la Always, schimbare de acuratețe etc.)
    private func configureForCurrentAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()

        if authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            // Prioritizăm continuitatea (grup de camping, poți sta pe loc ore în șir la
            // tabără) peste economia de baterie a pauzării automate.
            manager.pausesLocationUpdatesAutomatically = false
        }

        if manager.accuracyAuthorization == .reducedAccuracy, !hasRequestedFullAccuracy {
            hasRequestedFullAccuracy = true
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseLocationForGroupMap")
        }

        // Upgrade la Always doar din When In Use — requestAlwaysAuthorization() apelat direct
        // din .notDetermined echivalează cu when-in-use (comportament documentat Apple), de-aia
        // fluxul rămâne în 2 pași: when-in-use la prima cerere, apoi upgrade aici.
        if authorizationStatus == .authorizedWhenInUse, !hasRequestedAlwaysUpgrade {
            hasRequestedAlwaysUpgrade = true
            manager.requestAlwaysAuthorization()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        configureForCurrentAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Continuăm cu ultima poziție cunoscută sau mock data
    }
}
