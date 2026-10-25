import SwiftUI

/// Pick the spot Swellbar reports on: search a beach or town (or type "lat, lon"), and the
/// nearest buoy, wind station and tide station are found automatically.
struct SpotPicker: View {
    let current: Spot
    var preview: (query: String, spot: Spot?)? = nil // for README screenshots
    let done: (Spot?) -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var finding = false
    @State private var picked: Spot?
    @State private var surfline = ""

    private static let directions: [(String, Double)] = [("N", 0), ("NE", 45), ("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where do you surf?").font(.system(size: 20, weight: .bold))
            HStack {
                TextField("Beach, town or \"lat, lon\"", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if searching {
                ProgressView().controlSize(.small)
            } else if !results.isEmpty && picked == nil {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { place in
                        Button { choose(place) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name)
                                Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if finding {
                HStack { ProgressView().controlSize(.small); Text("Finding the nearest buoys and stations…").foregroundStyle(.secondary) }
            }
            if let spot = picked {
                details(spot)
            } else if !finding {
                Button("Use Del Mar, CA") { picked = .delMar; surfline = Spot.delMar.surflineURL ?? "" }
                    .buttonStyle(.link)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Now: \(current.name)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Use This Spot") {
                    guard var spot = picked else { return }
                    let url = surfline.trimmingCharacters(in: .whitespaces)
                    spot.surflineURL = url.isEmpty ? nil : url
                    done(spot)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .frame(minHeight: 520, alignment: .top)
        .onAppear {
            if let preview {
                query = preview.query
                picked = preview.spot
            }
        }
    }

    private func details(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(spot.name).font(.headline)
                Text(spot.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                row("Waves", "water.waves", spot.waveBuoy, missing: "No buoy nearby: using the Open-Meteo wave model")
                if let outer = spot.outerBuoy { row("Outer buoy", "dot.radiowaves.left.and.right", outer, missing: "") }
                row("Wind", "wind", spot.windStation, missing: "No station nearby: using the Open-Meteo forecast")
                row("Tide", "arrow.up.and.down", spot.tideStation, missing: "No NOAA tide station nearby (US only)")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Beach faces").font(.subheadline.weight(.semibold))
                Picker("", selection: Binding(get: { nearestDirection(spot.facingDeg) }, set: { picked?.facingDeg = $0 })) {
                    ForEach(Self.directions, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("The way you look when you face the waves. Sets which wind counts as offshore.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Surfline page (optional)").font(.subheadline.weight(.semibold))
                TextField("https://www.surfline.com/surf-report/…", text: $surfline).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func row(_ label: String, _ icon: String, _ station: Station?, missing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            Text(label).font(.caption.weight(.semibold)).frame(width: 66, alignment: .leading)
            if let s = station {
                Text("\(s.name) (\(s.id))\(s.km.map { String(format: " · %.0f km", $0) } ?? "")").font(.caption)
            } else {
                Text(missing).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // The exact saved angle (e.g. Del Mar's 265) shows as its nearest of the 8 directions.
    private func nearestDirection(_ deg: Double) -> Double {
        Self.directions.min { abs(angleDiff($0.1, deg)) < abs(angleDiff($1.1, deg)) }!.1
    }

    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? d - 360 : d < -180 ? d + 360 : d
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        picked = nil
        searching = true
        Task {
            results = await PlaceSearch.search(q)
            searching = false
            if results.count == 1 { choose(results[0]) }
        }
    }

    private func choose(_ place: Place) {
        finding = true
        picked = nil
        Task {
            let spot = await StationFinder.spot(for: place)
            picked = spot
            surfline = ""
            finding = false
        }
    }
}

/// A strip of menu bar showing Swellbar's title, for the README.
struct MenuBarPreview: View {
    let title: NSAttributedString

    var body: some View {
        HStack(spacing: 14) {
            Text(AttributedString(title))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Sat 7:42 AM")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(white: 0.18))
    }
}
