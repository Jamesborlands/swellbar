import Charts
import SwiftUI

struct SurfPopover: View {
    @ObservedObject var model: SurfModel
    var changeSpot: () -> Void
    var scrolls = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder var body: some View {
        if scrolls {
            ScrollView(.vertical) { content }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: 380)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let report = model.report, let near = report.nearshore, let range = model.surfRange {
                hero(range: range, near: near)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    swellCard(report, near: near)
                    windCard(report)
                    waterCard(near)
                    weatherCard(report)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !report.tideCurve.isEmpty { tideCard(report) }
                if !report.forecast.isEmpty { forecastCard(report) }
                footer(report)
            } else if model.isLoading {
                ProgressView("Checking the buoys…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark").font(.title)
                    Text("Couldn't reach the buoy data.")
                    Button("Try Again") { model.refresh() }
                        .buttonStyle(.glassProminent)
                        .padding(.top, 4)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Button(action: changeSpot) {
                    HStack(spacing: 5) {
                        Text(model.spot.name).font(.title2.weight(.bold)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(HoverPlate())
                .help("Change spot")
                Text([model.spot.subtitle, model.report.map { "Updated \($0.fetchedAt.formatted(date: .omitted, time: .shortened))" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.isLoading)
                            .frame(width: 16, height: 16)
                    }
                    .help("Refresh")
                    settingsMenu
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
        }
    }

    private func hero(range: Surf.Range, near: BuoyReading) -> some View {
        let rating = model.rating ?? .fair
        return HStack(alignment: .center, spacing: 14) {
            Capsule()
                .fill(rating.color)
                .frame(width: 5, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(rating.label)
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                    // The yellows and greens wash out on light glass; deepen them a little there.
                    .foregroundStyle(colorScheme == .light ? rating.color.mix(with: .black, by: 0.25) : rating.color)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(range.lo)-\(range.hi)").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("ft\(range.plus ? "+" : "")").font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                Text(range.body).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func swellCard(_ report: SurfReport, near: BuoyReading) -> some View {
        Card(title: "SWELL", icon: "water.waves") {
            if let swell = report.swell {
                Text("\(swell.heightFt, specifier: "%.1f")ft · \(Int(swell.periodS.rounded()))s")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("\(swell.direction)\(near.directionDeg.map { " \(Int($0))°" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(near.heightFt, specifier: "%.1f")ft · \(Int(near.periodS))s")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            if let wind = report.windSwell, wind.heightFt >= 0.3 {
                Text("+ \(wind.heightFt, specifier: "%.1f")ft \(Int(wind.periodS.rounded()))s \(wind.direction) windswell")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func windCard(_ report: SurfReport) -> some View {
        Card(title: "WIND", icon: "wind") {
            if let wind = report.wind {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(wind.speedKts.rounded()))").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("kts \(Surf.compass(wind.directionDeg))").font(.callout)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(wind.directionDeg + 180))
                        .foregroundStyle(.secondary)
                }
                let kind = Surf.windKind(fromDeg: wind.directionDeg, offshoreFrom: model.spot.offshoreFromDeg)
                Text(kind.rawValue + (wind.gustKts.map { ", gusts \(Int($0.rounded()))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(kind == .offshore ? Color.green : kind == .onshore ? Color.orange : Color.secondary)
            } else {
                Text("—").font(.system(size: 17, weight: .semibold))
            }
        }
    }

    private func waterCard(_ near: BuoyReading) -> some View {
        Card(title: "WATER", icon: "thermometer.medium") {
            if let water = near.waterTempF {
                Text("\(Int(water.rounded()))°F").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(Surf.wetsuit(waterF: water)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 17, weight: .semibold))
            }
        }
    }

    private func weatherCard(_ report: SurfReport) -> some View {
        Card(title: "WEATHER", icon: "sun.max") {
            if let now = report.hourly.first {
                Text("\(now.tempF)°F").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(now.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("—").font(.system(size: 17, weight: .semibold))
            }
        }
    }

    private func tideCard(_ report: SurfReport) -> some View {
        Card(title: "TIDE · \((model.spot.tideStation?.name ?? "").uppercased())", icon: "arrow.up.and.down") {
            HStack(alignment: .firstTextBaseline) {
                if let now = report.tideNow {
                    Text("\(now.heightFt, specifier: "%.1f")ft").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Image(systemName: now.rising ? "arrow.up.right" : "arrow.down.right").font(.caption)
                    Text(now.rising ? "Rising" : "Falling").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    ForEach(report.tideEvents.filter { $0.time > Date() }.prefix(3)) { event in
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(event.isHigh ? "High" : "Low") \(event.heightFt, specifier: "%.1f")ft")
                                .font(.system(size: 10, weight: .semibold))
                            Text(event.time.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !report.tideCurve.isEmpty {
                Chart {
                    ForEach(report.tideCurve) { point in
                        AreaMark(x: .value("Time", point.time), y: .value("Feet", point.heightFt))
                            .foregroundStyle(LinearGradient(colors: [Color.cyan.opacity(0.45), Color.cyan.opacity(0.05)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", point.time), y: .value("Feet", point.heightFt))
                            .foregroundStyle(Color.cyan)
                            .interpolationMethod(.catmullRom)
                    }
                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))") } }
                    }
                }
                .frame(height: 80)
            }
        }
    }

    private func forecastCard(_ report: SurfReport) -> some View {
        Card(title: "NEXT \(report.forecast.count) DAYS", icon: "calendar") {
            ForEach(report.forecast) { day in
                let range = Surf.range(day.surfFt)
                let rating = Surf.rating(range: range, periodS: day.periodS, wind: day.wind, offshoreFrom: model.spot.offshoreFromDeg)
                HStack(spacing: 8) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption).frame(width: 40, alignment: .leading)
                    Circle().fill(rating.color).frame(width: 7, height: 7)
                    Text(range.spaced).font(.system(size: 12, weight: .semibold, design: .rounded)).frame(width: 58, alignment: .leading)
                    Text("\(Int(day.periodS.rounded()))s").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                    if let wind = day.wind {
                        let kind = Surf.windKind(fromDeg: wind.directionDeg, offshoreFrom: model.spot.offshoreFromDeg)
                        Text("\(Int(wind.speedKts.rounded()))kt \(Surf.compass(wind.directionDeg))")
                            .font(.system(size: 11))
                            .foregroundStyle(kind == .offshore ? Color.green : kind == .onshore ? Color.orange : Color.secondary)
                            .frame(width: 58, alignment: .leading)
                    }
                    Spacer()
                    Text([day.highF.map { "\($0)°" }, day.summary.isEmpty ? nil : day.summary].compactMap { $0 }.joined(separator: " "))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(report.wavesFromModel ? "Wave model · morning wind" : "Wave model scaled to today's buoy · morning wind")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private func footer(_ report: SurfReport) -> some View {
        let spot = model.spot
        var parts: [String] = []
        parts.append(report.wavesFromModel ? "Waves: Open-Meteo model" : "Waves: NDBC \(spot.waveBuoy?.id ?? "")")
        parts.append(report.windFromModel ? "Wind: Open-Meteo" : "Wind: NDBC \(spot.windStation?.id ?? "")")
        if let tide = spot.tideStation { parts.append("Tide: NOAA \(tide.id)") }
        parts.append("Weather + forecast: Open-Meteo")
        return HStack(alignment: .center, spacing: 10) {
            Text(parts.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button { SurflineWindow.show(spot) } label: {
                HStack(spacing: 3) {
                    Text("Surfline")
                    Image(systemName: "arrow.up.forward").font(.caption2.weight(.semibold))
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .help("Open Surfline's report for \(spot.name)")
        }
        .padding(.horizontal, 2)
    }

    private var settingsMenu: some View {
        Menu {
            Button("Change Spot…", action: changeSpot)
            Divider()
            Toggle("Open at Login", isOn: Binding(get: { launchAtLogin }, set: {
                LoginItem.set($0)
                launchAtLogin = LoginItem.isEnabled
            }))
            Divider()
            Button("Quit Swellbar") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 32, height: 32)
        .contentShape(Circle())
        .glassEffect(.regular.interactive(), in: Circle()) // the glass button style doesn't reach menus
        .help("Settings")
    }
}

/// A report module: a quiet fill like a Control Center module, so the glass stays on the controls.
struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A borderless button that shows a soft plate on hover and press, like a toolbar title menu.
struct HoverPlate: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

    private struct Plate: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary.opacity(configuration.isPressed ? 1 : hovering ? 0.6 : 0),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .padding(.horizontal, -6)
        }
    }
}
