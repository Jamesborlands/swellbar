import Foundation
import MapKit

/// A data station near the spot (NDBC buoy or shore station, or NOAA tide station).
struct Station: Codable, Equatable {
    var id: String
    var name: String
    var km: Double? = nil // distance from the spot, shown in the picker
}

/// The surf spot Swellbar reports on, with the stations that feed it. Saved in UserDefaults.
struct Spot: Codable, Equatable {
    var name: String
    var subtitle: String
    var lat: Double
    var lon: Double
    /// The compass direction the beach faces (looking out at the waves). Wind from the
    /// opposite direction is offshore.
    var facingDeg: Double
    var waveBuoy: Station?   // nil: waves come from the Open-Meteo wave model
    var outerBuoy: Station?
    var windStation: Station? // nil: wind comes from the Open-Meteo forecast
    var tideStation: Station? // nil: no tide card (NOAA tide predictions are US only)
    var surflineURL: String?

    var offshoreFromDeg: Double { (facingDeg + 180).truncatingRemainder(dividingBy: 360) }

    var surflinePage: URL {
        if let s = surflineURL, let url = URL(string: s), url.scheme?.hasPrefix("http") == true { return url }
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "https://www.surfline.com/search/\(q)")!
    }

    static let delMar = Spot(
        name: "Del Mar", subtitle: "North San Diego, CA", lat: 32.959, lon: -117.269, facingDeg: 265,
        waveBuoy: Station(id: "46266", name: "Del Mar Nearshore"),
        outerBuoy: Station(id: "46225", name: "Torrey Pines Outer"),
        windStation: Station(id: "LJPC1", name: "Scripps Pier"),
        tideStation: Station(id: "9410230", name: "La Jolla (Scripps Pier)"),
        surflineURL: "https://www.surfline.com/surf-report/del-mar/5842041f4e65fad6a77088af")
}

enum SpotStore {
    private static let key = "spot"

    static var hasSaved: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func load() -> Spot {
        guard let data = UserDefaults.standard.data(forKey: key), let spot = try? JSONDecoder().decode(Spot.self, from: data) else { return .delMar }
        return spot
    }

    static func save(_ spot: Spot) {
        if let data = try? JSONEncoder().encode(spot) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// A place from the search box.
struct Place: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let lat: Double
    let lon: Double
}

enum PlaceSearch {
    /// Apple Maps search, or a typed "lat, lon".
    static func search(_ query: String) async -> [Place] {
        let parts = query.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, let lat = parts[0], let lon = parts[1], abs(lat) <= 90, abs(lon) <= 180 {
            return [Place(name: String(format: "%.4f, %.4f", lat, lon), subtitle: "Coordinates", lat: lat, lon: lon)]
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(8).map { item in
            let p = item.placemark
            let sub = [p.locality, p.administrativeArea, p.country].compactMap { $0 }.filter { $0 != item.name }
            return Place(name: item.name ?? "Unnamed", subtitle: sub.joined(separator: ", "),
                         lat: p.coordinate.latitude, lon: p.coordinate.longitude)
        }
    }
}

/// Finds the stations nearest a spot from NOAA's public station lists.
enum StationFinder {
    static let waveRadiusKm = 80.0
    static let windRadiusKm = 40.0
    static let tideRadiusKm = 80.0

    static func spot(for place: Place) async -> Spot {
        async let obs = SurfAPI.text("https://www.ndbc.noaa.gov/data/latest_obs/latest_obs.txt")
        async let active = SurfAPI.text("https://www.ndbc.noaa.gov/activestations.xml")
        async let tides = SurfAPI.json("https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions")

        let names = stationNames(await active ?? "")
        var waves: [(Station, lat: Double, lon: Double)] = []
        var winds: [Station] = []
        for line in (await obs ?? "").split(separator: "\n") where !line.hasPrefix("#") {
            let c = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard c.count > 12, let lat = Double(c[1]), let lon = Double(c[2]) else { continue }
            let km = distanceKm(place.lat, place.lon, lat, lon)
            let station = Station(id: c[0], name: names[c[0]] ?? "Station \(c[0])", km: km)
            if let h = Double(c[11]), h > 0, let p = Double(c[12]), p > 0, km <= waveRadiusKm * 1.5 { waves.append((station, lat, lon)) }
            if Double(c[9]) != nil, km <= windRadiusKm { winds.append(station) }
        }
        waves.sort { $0.0.km! < $1.0.km! }
        winds.sort { $0.km! < $1.km! }

        let near = waves.first.flatMap { $0.0.km! <= waveRadiusKm ? $0 : nil }
        let outer = waves.dropFirst().first { w in
            guard let near else { return false }
            return w.0.km! <= waveRadiusKm * 1.5 && distanceKm(near.lat, near.lon, w.lat, w.lon) >= 3
        }

        var tide: Station?
        if let list = (await tides as? [String: Any])?["stations"] as? [[String: Any]] {
            tide = list.compactMap { s -> Station? in
                guard let id = s["id"] as? String, let lat = s["lat"] as? Double, let lon = s["lng"] as? Double else { return nil }
                let km = distanceKm(place.lat, place.lon, lat, lon)
                return km <= tideRadiusKm ? Station(id: id, name: s["name"] as? String ?? id, km: km) : nil
            }.min { $0.km! < $1.km! }
        }

        // Buoys sit offshore, so the direction to the nearest one is a decent guess at
        // which way the beach faces. West if there's no buoy. The picker lets you fix it.
        let facing = near.map { bearing(place.lat, place.lon, $0.lat, $0.lon) } ?? 270
        return Spot(name: place.name, subtitle: place.subtitle, lat: place.lat, lon: place.lon,
                    facingDeg: ((facing / 45).rounded() * 45).truncatingRemainder(dividingBy: 360), waveBuoy: near?.0, outerBuoy: outer?.0,
                    windStation: winds.first, tideStation: tide, surflineURL: nil)
    }

    private static func stationNames(_ xml: String) -> [String: String] {
        guard let re = try? NSRegularExpression(pattern: #"<station id="([^"]+)"[^>]*? name="([^"]*)""#) else { return [:] }
        var names: [String: String] = [:]
        let ns = xml as NSString
        for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 2))
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&apos;", with: "'")
            names[ns.substring(with: m.range(at: 1)).uppercased()] = name
        }
        return names
    }

    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((lat2 - lat1) * r / 2), 2) + cos(lat1 * r) * cos(lat2 * r) * pow(sin((lon2 - lon1) * r / 2), 2)
        return 2 * 6371 * asin(sqrt(a))
    }

    static func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let y = sin((lon2 - lon1) * r) * cos(lat2 * r)
        let x = cos(lat1 * r) * sin(lat2 * r) - sin(lat1 * r) * cos(lat2 * r) * cos((lon2 - lon1) * r)
        return (atan2(y, x) / r + 360).truncatingRemainder(dividingBy: 360)
    }
}
