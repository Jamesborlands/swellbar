import SwiftUI

/// Turns buoy readings into Surfline-style surf heights, ratings and labels.
enum Surf {
    /// Scales the Komar–Gaughan breaking-height estimate to match Surfline's Del Mar numbers.
    /// Calibrated 2026-10-18: Del Mar Nearshore buoy 0.7 m @ 17 s, Surfline reported 3–4 ft+.
    static let calibration = 0.80

    /// Del Mar's beaches face roughly west, so wind *from* the east is offshore.
    static let offshoreFromDeg = 85.0

    static func breakingHeightFt(buoyHeightFt: Double, periodS: Double) -> Double {
        let h = buoyHeightFt * 0.3048
        let hb = 0.39 * pow(9.81, 0.2) * pow(periodS * h * h, 0.4) * calibration
        return hb / 0.3048
    }

    struct Range {
        let lo: Int
        let hi: Int
        let plus: Bool

        var text: String { "\(lo)-\(hi)ft\(plus ? "+" : "")" }
        var spaced: String { "\(lo)–\(hi) ft\(plus ? "+" : "")" }

        var body: String {
            switch lo {
            case 0: return "Flat to ankle"
            case 1: return plus ? "Shin to thigh" : "Ankle to knee"
            case 2: return plus ? "Thigh to stomach" : "Knee to waist"
            case 3: return plus ? "Waist to shoulder" : "Waist to chest"
            case 4: return plus ? "Shoulder to head high" : "Shoulder to head"
            case 5...6: return "Head high to overhead"
            case 7...9: return "Overhead to well overhead"
            default: return "Double overhead+"
            }
        }
    }

    static func range(_ ft: Double) -> Range {
        guard ft >= 1 else { return Range(lo: 0, hi: 1, plus: ft >= 0.6) }
        let lo = Int(ft)
        let plus = ft - Double(lo) >= 0.5
        switch lo {
        case ..<5: return Range(lo: lo, hi: lo + 1, plus: plus)
        case 5..<10: return Range(lo: lo, hi: lo + 2, plus: plus)
        default: return Range(lo: lo, hi: lo + 3, plus: plus)
        }
    }

    enum WindKind: String {
        case offshore = "Offshore", crossShore = "Cross-shore", onshore = "Onshore"
    }

    static func windKind(fromDeg: Double) -> WindKind {
        var diff = abs(fromDeg - offshoreFromDeg).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        switch diff {
        case ..<50: return .offshore
        case ..<130: return .crossShore
        default: return .onshore
        }
    }

    static func compass(_ deg: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((deg.truncatingRemainder(dividingBy: 360) + 11.25) / 22.5) % 16
        return points[index]
    }

    enum Rating: Int {
        case flat = -1, veryPoor, poor, poorToFair, fair, fairToGood, good, epic

        var label: String {
            switch self {
            case .flat: return "FLAT"
            case .veryPoor: return "VERY POOR"
            case .poor: return "POOR"
            case .poorToFair: return "POOR TO FAIR"
            case .fair: return "FAIR"
            case .fairToGood: return "FAIR TO GOOD"
            case .good: return "GOOD"
            case .epic: return "EPIC"
            }
        }

        var color: Color { Color(nsColor) }

        var nsColor: NSColor {
            switch self {
            case .flat: return .systemGray
            case .veryPoor: return NSColor(srgbRed: 0.93, green: 0.27, blue: 0.27, alpha: 1)
            case .poor: return NSColor(srgbRed: 1.0, green: 0.55, blue: 0.20, alpha: 1)
            case .poorToFair: return NSColor(srgbRed: 1.0, green: 0.80, blue: 0.20, alpha: 1)
            case .fair: return NSColor(srgbRed: 0.18, green: 0.80, blue: 0.44, alpha: 1)
            case .fairToGood: return NSColor(srgbRed: 0.10, green: 0.75, blue: 0.75, alpha: 1)
            case .good: return NSColor(srgbRed: 0.25, green: 0.50, blue: 1.0, alpha: 1)
            case .epic: return NSColor(srgbRed: 0.60, green: 0.35, blue: 1.0, alpha: 1)
            }
        }
    }

    /// A rough quality call from size, period and wind — Swellbar's own estimate, not Surfline's forecaster rating.
    static func rating(range: Range, periodS: Double, wind: WindReading?) -> Rating {
        guard range.hi > 1 || range.plus else { return .flat }
        var level: Int
        switch range.lo {
        case ..<2: level = Rating.poor.rawValue
        case 2: level = Rating.poorToFair.rawValue
        case 3...5: level = Rating.fair.rawValue
        default: level = Rating.fairToGood.rawValue
        }
        if periodS >= 14 && range.lo >= 4 { level += 1 }
        if let wind {
            switch windKind(fromDeg: wind.directionDeg) {
            case .onshore where wind.speedKts >= 10: level -= 2
            case .onshore where wind.speedKts >= 6: level -= 1
            case .crossShore where wind.speedKts >= 12: level -= 1
            default: break
            }
        }
        return Rating(rawValue: min(max(level, 0), Rating.epic.rawValue)) ?? .fair
    }

    static func wetsuit(waterF: Double) -> String {
        switch waterF {
        case 74...: return "Boardshorts"
        case 70..<74: return "2mm springsuit"
        case 66..<70: return "3/2 fullsuit"
        case 60..<66: return "4/3 fullsuit"
        case 55..<60: return "5/4 + booties"
        default: return "5/4 + hood"
        }
    }
}
