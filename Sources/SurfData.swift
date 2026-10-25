import Foundation

struct BuoyReading {
    let time: Date
    let heightFt: Double
    let periodS: Double
    let directionDeg: Double?
    let waterTempF: Double?
}

struct SwellComponent {
    let heightFt: Double
    let periodS: Double
    let direction: String
}

struct WindReading {
    let time: Date
    let speedKts: Double
    let gustKts: Double?
    let directionDeg: Double
}

struct TidePoint: Identifiable {
    let time: Date
    let heightFt: Double
    var id: Date { time }
}

struct TideEvent: Identifiable {
    let time: Date
    let heightFt: Double
    let isHigh: Bool
    var id: Date { time }
}

struct HourlyWeather: Identifiable {
    let time: Date
    let tempF: Int
    let windKts: Double
    let windDirection: String
    let summary: String
    var id: Date { time }
}

struct SurfReport {
    var nearshore: BuoyReading?
    var nearshoreHistory: [BuoyReading] = []
    var outer: BuoyReading?
    var swell: SwellComponent?
    var windSwell: SwellComponent?
    var wind: WindReading?
    var tideCurve: [TidePoint] = []
    var tideEvents: [TideEvent] = []
    var hourly: [HourlyWeather] = []
    var fetchedAt = Date()

    /// Today's tide height right now, interpolated from the prediction curve.
    var tideNow: (heightFt: Double, rising: Bool)? {
        let now = Date()
        guard let after = tideCurve.firstIndex(where: { $0.time >= now }), after > 0 else { return nil }
        let a = tideCurve[after - 1], b = tideCurve[after]
        let t = now.timeIntervalSince(a.time) / b.time.timeIntervalSince(a.time)
        return (a.heightFt + (b.heightFt - a.heightFt) * t, b.heightFt > a.heightFt)
    }
}

/// Public data for Del Mar: CDIP buoys via NDBC, NOAA tides (La Jolla / Scripps Pier), NWS weather.
enum SurfAPI {
    static let nearshoreBuoy = "46266" // CDIP 153 Del Mar Nearshore
    static let outerBuoy = "46225" // CDIP 100 Torrey Pines Outer
    static let windStation = "LJPC1" // Scripps Pier, La Jolla
    static let tideStation = "9410230" // La Jolla (Scripps Pier)
    static let nwsHourly = "https://api.weather.gov/gridpoints/SGX/54,25/forecast/hourly"

    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Swellbar/1.0 (personal surf menu bar app)"]
        return URLSession(configuration: config)
    }()

    static func fetchReport() async -> SurfReport {
        async let nearText = text("https://www.ndbc.noaa.gov/data/realtime2/\(nearshoreBuoy).txt")
        async let nearSpec = text("https://www.ndbc.noaa.gov/data/realtime2/\(nearshoreBuoy).spec")
        async let outerText = text("https://www.ndbc.noaa.gov/data/realtime2/\(outerBuoy).txt")
        async let windText = text("https://www.ndbc.noaa.gov/data/realtime2/\(windStation).txt")
        async let tides = tideData()
        async let hourly = hourlyWeather()

        var report = SurfReport()
        if let rows = await nearText.map(ndbcRows) {
            let readings = rows.compactMap(buoyReading)
            report.nearshore = readings.first
            if let latest = readings.first {
                report.nearshoreHistory = readings.filter { latest.time.timeIntervalSince($0.time) <= 24 * 3600 }.reversed()
            }
        }
        if let rows = await nearSpec.map(ndbcRows), let row = rows.first(where: { num($0["SwH"]) != nil }) {
            if let h = num(row["SwH"]), let p = num(row["SwP"]) {
                report.swell = SwellComponent(heightFt: h * 3.28084, periodS: p, direction: row["SwD"] ?? "")
            }
            if let h = num(row["WWH"]), let p = num(row["WWP"]) {
                report.windSwell = SwellComponent(heightFt: h * 3.28084, periodS: p, direction: row["WWD"] ?? "")
            }
        }
        if let rows = await outerText.map(ndbcRows) {
            report.outer = rows.lazy.compactMap(buoyReading).first
        }
        if let rows = await windText.map(ndbcRows),
           let row = rows.first(where: { num($0["WSPD"]) != nil && num($0["WDIR"]) != nil }),
           let time = ndbcDate(row) {
            report.wind = WindReading(time: time, speedKts: num(row["WSPD"])! * 1.94384,
                                      gustKts: num(row["GST"]).map { $0 * 1.94384 }, directionDeg: num(row["WDIR"])!)
        }
        let tideResult = await tides
        report.tideCurve = tideResult.curve
        report.tideEvents = significantTides(tideResult.events)
        report.hourly = await hourly
        report.fetchedAt = Date()
        return report
    }

    // MARK: NDBC

    private static func ndbcRows(_ text: String) -> [[String: String]] {
        let lines = text.split(separator: "\n")
        guard let header = lines.first else { return [] }
        let keys = header.replacingOccurrences(of: "#", with: "").split(whereSeparator: \.isWhitespace).map(String.init)
        return lines.filter { !$0.hasPrefix("#") }.map { line in
            let values = line.split(whereSeparator: \.isWhitespace).map(String.init)
            return Dictionary(zip(keys, values), uniquingKeysWith: { a, _ in a })
        }
    }

    private static func ndbcDate(_ row: [String: String]) -> Date? {
        guard let y = row["YY"].flatMap(Int.init), let mo = row["MM"].flatMap(Int.init), let d = row["DD"].flatMap(Int.init),
              let h = row["hh"].flatMap(Int.init), let mi = row["mm"].flatMap(Int.init) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))
    }

    private static func buoyReading(_ row: [String: String]) -> BuoyReading? {
        guard let time = ndbcDate(row), let h = num(row["WVHT"]), let p = num(row["DPD"]) else { return nil }
        return BuoyReading(time: time, heightFt: h * 3.28084, periodS: p, directionDeg: num(row["MWD"]),
                           waterTempF: num(row["WTMP"]).map { $0 * 9 / 5 + 32 })
    }

    private static func num(_ value: String?) -> Double? {
        guard let value, value != "MM" else { return nil }
        return Double(value)
    }

    // MARK: Tides

    private static func tideData() async -> (curve: [TidePoint], events: [TideEvent]) {
        let formatter = DateFormatter()
        formatter.timeZone = pacific
        formatter.dateFormat = "yyyyMMdd"
        let today = formatter.string(from: Date())
        let base = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?station=\(tideStation)&product=predictions&datum=MLLW&units=english&time_zone=lst_ldt&format=json"
        async let curveJSON = json("\(base)&interval=15&begin_date=\(today)&range=24")
        async let eventJSON = json("\(base)&interval=hilo&begin_date=\(today)&range=48")

        let stamp = DateFormatter()
        stamp.timeZone = pacific
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        func predictions(_ object: Any?) -> [[String: String]] {
            ((object as? [String: Any])?["predictions"] as? [[String: String]]) ?? []
        }
        let curve = predictions(await curveJSON).compactMap { p -> TidePoint? in
            guard let t = p["t"].flatMap(stamp.date(from:)), let v = p["v"].flatMap(Double.init) else { return nil }
            return TidePoint(time: t, heightFt: v)
        }
        let events = predictions(await eventJSON).compactMap { p -> TideEvent? in
            guard let t = p["t"].flatMap(stamp.date(from:)), let v = p["v"].flatMap(Double.init) else { return nil }
            return TideEvent(time: t, heightFt: v, isHigh: p["type"] == "H")
        }
        return (curve, events)
    }

    /// Hides turns of under 0.3ft (Surfline skips a 0.1ft "low" sitting between two highs).
    static func significantTides(_ events: [TideEvent]) -> [TideEvent] {
        var result: [TideEvent] = []
        for event in events {
            if let last = result.last, abs(last.heightFt - event.heightFt) < 0.3 { continue }
            result.append(event)
        }
        return result
    }

    // MARK: Weather

    private static func hourlyWeather() async -> [HourlyWeather] {
        guard let object = await json(nwsHourly) as? [String: Any],
              let periods = (object["properties"] as? [String: Any])?["periods"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return periods.prefix(24).compactMap { p in
            guard let start = (p["startTime"] as? String).flatMap(iso.date(from:)),
                  let temp = p["temperature"] as? Int else { return nil }
            let mph = (p["windSpeed"] as? String)?.split(separator: " ").first.flatMap { Double($0) } ?? 0
            return HourlyWeather(time: start, tempF: temp, windKts: mph * 0.868976,
                                 windDirection: p["windDirection"] as? String ?? "", summary: p["shortForecast"] as? String ?? "")
        }
    }

    // MARK: Networking

    private static func text(_ url: String) async -> String? {
        guard let url = URL(string: url), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func json(_ url: String) async -> Any? {
        guard let url = URL(string: url), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
