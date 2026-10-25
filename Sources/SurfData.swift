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
    var wavesFromModel = false // no buoy: Open-Meteo wave model
    var windFromModel = false // no wind station: Open-Meteo forecast
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

/// Public data for any spot: NDBC buoys and shore stations, NOAA tide predictions, and
/// Open-Meteo for weather (and for waves and wind where there's no station nearby).
enum SurfAPI {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Swellbar/1.1 (github.com/Jamesborlands/swellbar)"]
        return URLSession(configuration: config)
    }()

    private static func ndbc(_ station: Station?, _ ext: String) async -> String? {
        guard let station else { return nil }
        return await text("https://www.ndbc.noaa.gov/data/realtime2/\(station.id).\(ext)")
    }

    static func fetchReport(spot: Spot) async -> SurfReport {
        async let nearText = ndbc(spot.waveBuoy, "txt")
        async let nearSpec = ndbc(spot.waveBuoy, "spec")
        async let outerText = ndbc(spot.outerBuoy, "txt")
        async let windText = ndbc(spot.windStation, "txt")
        async let tides = tideData(spot.tideStation)
        async let forecast = openMeteo(spot)

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
        // No buoy (or it's down): use the wave model. No wind station: forecast wind.
        if report.nearshore == nil, let model = await waveModel(spot) {
            report.nearshore = model.reading
            report.nearshoreHistory = model.history
            report.swell = model.swell
            report.windSwell = model.windSwell
            report.wavesFromModel = true
        }
        let weather = await forecast
        report.hourly = weather.hourly
        if report.wind == nil {
            report.wind = weather.wind
            report.windFromModel = weather.wind != nil
        }
        let tideResult = await tides
        report.tideCurve = tideResult.curve
        report.tideEvents = significantTides(tideResult.events)
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

    private static func tideData(_ station: Station?) async -> (curve: [TidePoint], events: [TideEvent]) {
        guard let station else { return ([], []) }
        let utc = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.timeZone = utc
        formatter.dateFormat = "yyyyMMdd HH:mm"
        // Curve: 12 hours either side of now. Highs and lows: the next two days.
        let curveStart = formatter.string(from: Date().addingTimeInterval(-12 * 3600))
        let eventStart = formatter.string(from: Date().addingTimeInterval(-3600))
        let base = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?station=\(station.id)&product=predictions&datum=MLLW&units=english&time_zone=gmt&format=json"
        let curveURL = "\(base)&interval=15&begin_date=\(curveStart.replacingOccurrences(of: " ", with: "%20"))&range=24"
        let eventURL = "\(base)&interval=hilo&begin_date=\(eventStart.replacingOccurrences(of: " ", with: "%20"))&range=48"
        async let curveJSON = json(curveURL)
        async let eventJSON = json(eventURL)

        let stamp = DateFormatter()
        stamp.timeZone = utc
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

    // MARK: Open-Meteo (worldwide, no key)

    private static let meteoTime: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    /// Hourly weather for the next 24 hours, plus current wind.
    private static func openMeteo(_ spot: Spot) async -> (hourly: [HourlyWeather], wind: WindReading?) {
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(spot.lat)&longitude=\(spot.lon)"
            + "&current=wind_speed_10m,wind_direction_10m,wind_gusts_10m"
            + "&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m&forecast_hours=24"
            + "&temperature_unit=fahrenheit&wind_speed_unit=kn&timezone=GMT"
        guard let object = await json(url) as? [String: Any] else { return ([], nil) }
        var wind: WindReading?
        if let c = object["current"] as? [String: Any], let speed = c["wind_speed_10m"] as? Double, let dir = c["wind_direction_10m"] as? Double {
            wind = WindReading(time: (c["time"] as? String).flatMap(meteoTime.date(from:)) ?? Date(),
                               speedKts: speed, gustKts: c["wind_gusts_10m"] as? Double, directionDeg: dir)
        }
        guard let h = object["hourly"] as? [String: Any], let times = h["time"] as? [String] else { return ([], wind) }
        let temps = h["temperature_2m"] as? [Double?] ?? [], codes = h["weather_code"] as? [Int?] ?? []
        let speeds = h["wind_speed_10m"] as? [Double?] ?? [], dirs = h["wind_direction_10m"] as? [Double?] ?? []
        let hourly = times.indices.compactMap { i -> HourlyWeather? in
            guard let t = meteoTime.date(from: times[i]), i < temps.count, let temp = temps[i] else { return nil }
            let code = i < codes.count ? codes[i] ?? 0 : 0
            return HourlyWeather(time: t, tempF: Int(temp.rounded()), windKts: i < speeds.count ? speeds[i] ?? 0 : 0,
                                 windDirection: i < dirs.count ? dirs[i].map(Surf.compass) ?? "" : "", summary: weatherSummary(code))
        }
        return (hourly, wind)
    }

    /// Modeled waves (Open-Meteo Marine) for spots without a buoy nearby.
    private static func waveModel(_ spot: Spot) async -> (reading: BuoyReading, history: [BuoyReading], swell: SwellComponent?, windSwell: SwellComponent?)? {
        let vars = "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,wind_wave_height,wind_wave_period,wind_wave_direction,sea_surface_temperature"
        let url = "https://marine-api.open-meteo.com/v1/marine?latitude=\(spot.lat)&longitude=\(spot.lon)"
            + "&current=\(vars)&hourly=wave_height,swell_wave_period,wave_period&past_days=1&forecast_days=1&timezone=GMT"
        guard let object = await json(url) as? [String: Any], let c = object["current"] as? [String: Any],
              let h = c["wave_height"] as? Double else { return nil }
        let period = (c["swell_wave_period"] as? Double) ?? (c["wave_period"] as? Double) ?? 0
        let reading = BuoyReading(time: (c["time"] as? String).flatMap(meteoTime.date(from:)) ?? Date(), heightFt: h * 3.28084,
                                  periodS: period, directionDeg: c["wave_direction"] as? Double,
                                  waterTempF: (c["sea_surface_temperature"] as? Double).map { $0 * 9 / 5 + 32 })
        func component(_ prefix: String) -> SwellComponent? {
            guard let h = c["\(prefix)_height"] as? Double, let p = c["\(prefix)_period"] as? Double else { return nil }
            return SwellComponent(heightFt: h * 3.28084, periodS: p, direction: (c["\(prefix)_direction"] as? Double).map(Surf.compass) ?? "")
        }
        var history: [BuoyReading] = []
        if let hr = object["hourly"] as? [String: Any], let times = hr["time"] as? [String],
           let heights = hr["wave_height"] as? [Double?] {
            let periods = hr["swell_wave_period"] as? [Double?] ?? []
            let now = Date()
            for i in times.indices where i < heights.count {
                guard let t = meteoTime.date(from: times[i]), t <= now, now.timeIntervalSince(t) <= 24 * 3600, let hh = heights[i] else { continue }
                history.append(BuoyReading(time: t, heightFt: hh * 3.28084, periodS: (i < periods.count ? periods[i] : nil) ?? period,
                                           directionDeg: nil, waterTempF: nil))
            }
        }
        return (reading, history, component("swell_wave"), component("wind_wave"))
    }

    /// WMO weather codes, as Open-Meteo reports them.
    private static func weatherSummary(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorms"
        default: return ""
        }
    }

    // MARK: Networking

    static func text(_ url: String) async -> String? {
        guard let url = URL(string: url), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func json(_ url: String) async -> Any? {
        guard let url = URL(string: url), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
