import SwiftUI
import UIKit

/// Photos des parcs, trouvées sur Wikipédia (illustration principale de l'article)
/// puis gardées en cache sur l'appareil.
@MainActor
final class ParkPhotoService: ObservableObject {
    static let shared = ParkPhotoService()

    @Published private(set) var images: [String: UIImage] = [:]
    private var loading: Set<String> = []

    private struct Lookup: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            struct Thumb: Decodable { let source: String }
            let index: Int?
            let thumbnail: Thumb?
        }
        let query: Query?
    }

    static func key(for park: Park) -> String {
        park.queueTimesID > 0 ? "qt\(park.queueTimesID)" : "n" + String(park.wName.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private func fileURL(_ key: String) -> URL { CacheStore.directory.appendingPathComponent("photo-\(key).jpg") }
    private func missURL(_ key: String) -> URL { CacheStore.directory.appendingPathComponent("photo-\(key).none") }

    func image(for park: Park) -> UIImage? {
        let key = Self.key(for: park)
        return images[key]
    }

    /// Cherche la photo si elle n'est pas encore en cache (un échec est retenté après 7 jours).
    func load(for park: Park) async {
        let key = Self.key(for: park)
        if images[key] != nil || loading.contains(key) { return }
        if let data = try? Data(contentsOf: fileURL(key)), let image = UIImage(data: data) {
            images[key] = image
            return
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: missURL(key).path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 7 * 86400 { return }
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let lookup = try await Network.get(Lookup.self, from: "https://en.wikipedia.org/w/api.php", query: [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "formatversion", value: "2"),
                URLQueryItem(name: "generator", value: "search"),
                URLQueryItem(name: "gsrsearch", value: park.wName),
                URLQueryItem(name: "gsrlimit", value: "3"),
                URLQueryItem(name: "prop", value: "pageimages"),
                URLQueryItem(name: "piprop", value: "thumbnail"),
                URLQueryItem(name: "pithumbsize", value: "1200")
            ])
            let candidates = (lookup.query?.pages ?? [])
                .sorted { ($0.index ?? 99) < ($1.index ?? 99) }
                .compactMap { $0.thumbnail?.source }
                .filter { url in
                    let l = url.lowercased()
                    return !l.contains("logo") && !l.contains(".svg") && !l.contains("map")
                }
            guard let source = candidates.first else { throw NetworkError.invalidData }
            let data = try await Network.getData(source)
            guard let image = UIImage(data: data) else { throw NetworkError.invalidData }
            let jpeg = image.jpegData(compressionQuality: 0.8) ?? data
            try? jpeg.write(to: fileURL(key), options: .atomic)
            images[key] = image
        } catch NetworkError.invalidData {
            try? Data().write(to: missURL(key))
        } catch {
            // Hors ligne : on réessaiera plus tard.
        }
    }
}

/// Fond d'en-tête : photo du parc assombrie pour garder le texte lisible,
/// sinon le dégradé de la couleur du voyage.
struct ParkPhotoBackground: View {
    let park: Park?
    let tint: Color
    /// Vignette : sans légende ni voile sombre.
    var compact = false
    @ObservedObject private var photos = ParkPhotoService.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let park, let image = photos.image(for: park) {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
                if !compact {
                LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.35), .black.opacity(0.70)],
                               startPoint: .top, endPoint: .bottom)
                Text("Photo : Wikipédia")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
                }
            } else {
                if !compact { Circle().fill(.white.opacity(0.14)).frame(width: 220).offset(x: 140, y: -110).blur(radius: 6) }
                else { Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.8)) }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: park.map { photos.image(for: $0) != nil } ?? false)
        .task(id: park?.objectID) {
            if let park { await photos.load(for: park) }
        }
    }
}

extension Trip {
    /// Parc qui illustre le voyage : celui du jour s'il y en a un, sinon le premier de la liste.
    func coverPark(now: Date = Date()) -> Park? {
        parks(on: DayKey.key(now)).first ?? parkList.first
    }
}
