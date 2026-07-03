import Foundation

// Contract de date partajat cu widget-ul de Home Screen, prin App Group
// (group.com.fancywrappers.FriendCamp) — NU printr-o dependință de cod, ci prin UserDefaults
// partajat, fiindcă widget-ul rulează într-un proces separat (extensie), fără acces direct la
// GroupDataStore/sesiunea Supabase din aplicația principală.
//
// IMPORTANT: acest fișier există IDENTIC în două locuri — FriendCamp/Services/WidgetSnapshot.swift
// (target FriendCamp) și FriendCampWidget/WidgetSnapshot.swift (target FriendCampWidgetExtension).
// Fiecare target folosește propriul folder sincronizat de Xcode (nu există un mecanism simplu de
// partajare a unui singur fișier între cele două foldere sincronizate) — orice modificare aici
// trebuie oglindită și în cealaltă copie.
struct WidgetSnapshot: Codable {
    var onlineCount: Int
    var totalCount: Int
    var lastActivityDate: Date?
    var latestPostTitle: String?
    var latestPostAuthor: String?
    var latestPostDate: Date?
    var generatedAt: Date

    static let suiteName = "group.com.fancywrappers.FriendCamp"
    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.suiteName)?.set(data, forKey: Self.key)
    }
}
