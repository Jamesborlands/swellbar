import Charts
import SwiftUI

struct SurfPopover: View {
    @ObservedObject var model: SurfModel
    var changeSpot: () -> Void
    var scrolls = true
    @State private var launchAtLogin = LoginItem.isEnabled

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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: changeSpot) {
                    HStack(spacing: 4) {
                        Text(model.spot.name).font(.system(size: 20, weight: .bold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Change spot")
                Text(model.spot.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let fetched = model.report?.fetchedAt {
                Text("Updated \(fetched.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.isLoading ? 360 : 0))
                    .animation(model.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isLoading)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            settingsMenu
        }
    }

    private func hero(range: Surf.Range, near: BuoyReading) -> some View {
        let rating = model.rating ?? .fair
        return HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(rating.color)
                .frame(width: 6, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text(rating.label)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(rating.color)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(range.lo)-\(range.hi)").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("ft\(range.plus ? "+" : "")").font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                Text(range.body).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
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
                        .foregroundStyle(.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
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
        return HStack(alignment: .firstTextBaseline) {
            Text(parts.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(.tertiary)
            Spacer()
            Button("Surfline") { SurflineWindow.show(spot) }
                .buttonStyle(.link)
                .font(.caption)
        }
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
        .fixedSize()
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }
}
