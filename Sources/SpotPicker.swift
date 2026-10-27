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
    @FocusState private var searchFocused: Bool

    private static let directions: [(String, Double)] = [("N", 0), ("NE", 45), ("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where do you surf?").font(.title.weight(.bold))
            searchField
            if !results.isEmpty && picked == nil && !finding {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { place in
                        Button { choose(place) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .red)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(place.name)
                                    if !place.subtitle.isEmpty {
                                        Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(RowPlate())
                    }
                }
                .padding(4)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if finding {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding the nearest buoys and stations…").foregroundStyle(.secondary)
                }
            }
            if let spot = picked {
                details(spot)
            } else if !finding && results.isEmpty && !searching {
                Button {
                    picked = .delMar
                    surfline = Spot.delMar.surflineURL ?? ""
                } label: {
                    Label("Use Del Mar, CA", systemImage: "location")
                }
                .buttonStyle(.glass)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Now: \(current.name)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Button("Use This Spot") {
                    guard var spot = picked else { return }
                    let url = surfline.trimmingCharacters(in: .whitespaces)
                    spot.surflineURL = url.isEmpty ? nil : url
                    done(spot)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(picked == nil)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .padding(.top, 30) // clear of the transparent title bar
        .frame(width: 460)
        .frame(minHeight: 500, alignment: .top)
        .onAppear {
            if let preview {
                query = preview.query
                picked = preview.spot
            }
            searchFocused = preview == nil
        }
        // Search as you type, once typing pauses.
        .task(id: query) {
            guard preview == nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(choosingSingle: false)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Beach, town or \"lat, lon\"", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { Task { await search(choosingSingle: true) } }
            if searching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .font(.title3)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.fill.quaternary, in: Capsule())
    }

    private func details(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spot.name).font(.headline)
                    Text(spot.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                row("Waves", "water.waves", spot.waveBuoy, missing: "No buoy nearby: using the Open-Meteo wave model")
                if let outer = spot.outerBuoy { row("Outer buoy", "dot.radiowaves.left.and.right", outer, missing: "") }
                row("Wind", "wind", spot.windStation, missing: "No station nearby: using the Open-Meteo forecast")
                row("Tide", "arrow.up.and.down", spot.tideStation, missing: "No NOAA tide station nearby (US only)")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                TextField("https://www.surfline.com/surf-report/…", text: $surfline)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    /// Return picks the place when only one matches (typed coordinates, a precise name).
    private func search(choosingSingle: Bool) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            searching = false
            return
        }
        picked = nil
        searching = true
        let found = await PlaceSearch.search(q)
        guard q == query.trimmingCharacters(in: .whitespaces) else { return } // typed on meanwhile
        results = found
        searching = false
        if choosingSingle && found.count == 1 { choose(found[0]) }
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

/// A list row that highlights on hover, like a menu or sidebar row.
struct RowPlate: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

    private struct Plate: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.fill.secondary.opacity(configuration.isPressed ? 1 : hovering ? 0.6 : 0),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
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
