import Foundation
import PulsoStore

/// Minimal RFC-4180 CSV reader (quoted fields, embedded commas/quotes/newlines).
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n":
                    row.append(field); field = ""
                    rows.append(row); row = []
                case "\r": break
                default: field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    public static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

/// Imports the `physiological_cycles.csv` file from a WHOOP data export so recovery baselines
/// (HRV, resting HR, respiration, skin temperature) are warm from day one.
public enum WhoopExportImporter {
    public struct Result: Equatable {
        public var days: Int
        public var skipped: Int
    }

    static func column(_ header: [String], _ needles: [String]) -> Int? {
        let lower = header.map { $0.lowercased() }
        for n in needles {
            if let i = lower.firstIndex(where: { $0.contains(n) }) { return i }
        }
        return nil
    }

    static func parseDate(_ s: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "MM/dd/yyyy HH:mm", "yyyy-MM-dd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }

    public static func parse(csv text: String, calendar: Calendar = .current) -> [DaySummary] {
        let rows = CSV.parse(text)
        guard let header = rows.first, rows.count > 1 else { return [] }
        let cWake = column(header, ["wake onset"])
        let cStart = column(header, ["cycle start"])
        let cRec = column(header, ["recovery score"])
        let cRHR = column(header, ["resting heart rate"])
        let cHRV = column(header, ["heart rate variability"])
        let cTemp = column(header, ["skin temp"])
        let cSpO2 = column(header, ["blood oxygen"])
        let cStrain = column(header, ["day strain"])
        let cResp = column(header, ["respiratory rate"])
        let cAsleep = column(header, ["asleep duration"])
        let cInBed = column(header, ["in bed duration"])
        let cNeed = column(header, ["sleep need"])
        let cPerf = column(header, ["sleep performance"])
        let cMaxHR = column(header, ["max hr"])
        let cOnset = column(header, ["sleep onset"])

        func num(_ row: [String], _ c: Int?) -> Double? {
            guard let c, c < row.count else { return nil }
            return Double(row[c].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
        }

        var out: [String: DaySummary] = [:]
        for row in rows.dropFirst() {
            var date: Date?
            if let c = cWake, c < row.count { date = parseDate(row[c]) }
            if date == nil, let c = cStart, c < row.count, let d = parseDate(row[c]) {
                date = calendar.date(byAdding: .hour, value: 12, to: d)
            }
            guard let d = date else { continue }
            var s = DaySummary(day: DayKey.string(d, calendar: calendar))
            s.source = "whoop"
            s.recovery = num(row, cRec)
            s.rhr = num(row, cRHR)
            s.hrv = num(row, cHRV)
            s.skinTemp = num(row, cTemp)
            s.spo2 = num(row, cSpO2)
            s.strain = num(row, cStrain)
            s.respRate = num(row, cResp)
            s.sleepMinutes = num(row, cAsleep)
            s.inBedMinutes = num(row, cInBed)
            s.sleepNeedMinutes = num(row, cNeed)
            s.sleepPerformance = num(row, cPerf).map { $0 / 100 }
            s.maxHR = num(row, cMaxHR)
            if let c = cOnset, c < row.count, let o = parseDate(row[c]) { s.sleepStart = Int(o.timeIntervalSince1970) }
            if let c = cWake, c < row.count, let w = parseDate(row[c]) { s.sleepEnd = Int(w.timeIntervalSince1970) }
            s.calibrating = false
            guard s.hrv != nil || s.rhr != nil || s.strain != nil else { continue }
            out[s.day] = s
        }
        return out.values.sorted { $0.day < $1.day }
    }
}

/// CSV exports of everything the app knows.
public enum Exporter {
    static func f(_ v: Double?, _ digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(digits)f", v)
    }

    public static func daysCSV(_ days: [DaySummary]) -> String {
        var lines = ["fecha,recuperacion,vfc_ms,fc_reposo,respiracion,spo2,temp_piel,desv_temp,esfuerzo,kcal,kcal_activas,pasos,fc_media,fc_max,sueno_min,en_cama_min,necesidad_min,rendimiento_sueno,eficiencia,consistencia,deuda_min,profundo_min,rem_min,ligero_min,despierto_min,estres_medio,vo2max,fuente"]
        for d in days {
            let cols: [String] = [
                d.day, f(d.recovery, 0), f(d.hrv), f(d.rhr), f(d.respRate), f(d.spo2), f(d.skinTemp, 2), f(d.skinTempDeviation, 2),
                f(d.strain), f(d.kcal, 0), f(d.activeKcal, 0), d.steps.map(String.init) ?? "", f(d.avgHR, 0), f(d.maxHR, 0),
                f(d.sleepMinutes, 0), f(d.inBedMinutes, 0), f(d.sleepNeedMinutes, 0), f(d.sleepPerformance.map { $0 * 100 }, 0),
                f(d.sleepEfficiency.map { $0 * 100 }, 0), f(d.sleepConsistency, 0), f(d.sleepDebtMinutes, 0),
                f(d.deepMinutes, 0), f(d.remMinutes, 0), f(d.lightMinutes, 0), f(d.awakeMinutes, 0),
                f(d.stressAvg, 2), f(d.vo2max), d.source,
            ]
            lines.append(cols.map(CSV.escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func samplesCSV(_ samples: [Sample]) -> String {
        var lines = ["unix,fc,rr_ms,grav_x,grav_y,grav_z,mov_g,temp_c,spo2,pasos_contador,actividad,estado_sueno,calidad,senal_pobre,fuera_muneca"]
        lines.reserveCapacity(samples.count + 1)
        for s in samples {
            let cols: [String] = [
                String(s.ts), s.hr.map(String.init) ?? "", s.rr.map(String.init).joined(separator: " "),
                f(s.gx, 4), f(s.gy, 4), f(s.gz, 4), f(s.dyn, 4), f(s.temp, 2), s.spo2.map(String.init) ?? "",
                s.steps.map(String.init) ?? "", s.activity.map(String.init) ?? "", s.sleepState.map(String.init) ?? "",
                s.quality.map(String.init) ?? "", s.poor ? "1" : "0", s.off ? "1" : "0",
            ]
            lines.append(cols.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func workoutsCSV(_ workouts: [Workout]) -> String {
        var lines = ["inicio,fin,deporte,origen,duracion_min,esfuerzo,fc_media,fc_max,kcal,z1,z2,z3,z4,z5"]
        let iso = ISO8601DateFormatter()
        for w in workouts {
            let cols: [String] = [
                iso.string(from: Date(timeIntervalSince1970: TimeInterval(w.start))),
                iso.string(from: Date(timeIntervalSince1970: TimeInterval(w.end))),
                w.sport, w.source.rawValue, f(w.durationMinutes, 0), f(w.strain), f(w.avgHR, 0), f(w.maxHR, 0), f(w.kcal, 0),
            ] + w.zoneMinutes.map { f($0, 0) }
            lines.append(cols.map(CSV.escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
