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

/// Reads the CSV files of a WHOOP data export, in English or in Spanish: `physiological_cycles.csv`,
/// `sleeps.csv` / `sueño.csv`, `workouts.csv` / `entrenamientos.csv` and `journal_entries.csv`.
/// Every file is optional and recognised by its header, not its name. Times are wall-clock in each
/// row's cycle time zone ("UTC+01:00").
public enum WhoopExport {
    public enum Kind: String, CaseIterable, Sendable {
        case cycles, sleeps, workouts, journal

        public var label: String {
            switch self {
            case .cycles: return "Ciclos (recuperación, VFC, esfuerzo)"
            case .sleeps: return "Sueño"
            case .workouts: return "Entrenamientos"
            case .journal: return "Diario"
            }
        }

        public var fileName: String {
            switch self {
            case .cycles: return "physiological_cycles.csv"
            case .sleeps: return "sleeps.csv · sueño.csv"
            case .workouts: return "workouts.csv · entrenamientos.csv"
            case .journal: return "journal_entries.csv"
            }
        }
    }

    public struct File: Sendable {
        public var name: String
        public var text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public struct FileReport: Equatable, Sendable {
        public var name: String
        /// nil when the header is not one of WHOOP's.
        public var kind: Kind?
        public var rows: Int
        /// Rows turned into days, workouts or journal answers.
        public var used: Int
        public var skipped: Int { max(0, rows - used) }
    }

    public struct Bundle: Sendable {
        public var days: [DaySummary] = []
        public var workouts: [Workout] = []
        public var journal: [JournalEntry] = []
        public var files: [FileReport] = []
    }

    // MARK: Columns (English and Spanish headers, compared without case or accents)

    enum Col: CaseIterable {
        case cycleStart, cycleEnd, timeZone, recovery, rhr, hrv, skinTemp, spo2, dayStrain, energy, maxHR, avgHR
        case sleepOnset, wakeOnset, performance, respRate, asleep, inBed, light, deep, rem, awake, need, debt
        case efficiency, consistency, nap
        case workoutStart, workoutEnd, activity, activityStrain, zone1, zone2, zone3, zone4, zone5, distance
        case question, answer

        /// Substrings of the normalised header; a leading "=" asks for the whole header.
        var needles: [String] {
            switch self {
            case .cycleStart: return ["cycle start time", "hora de inicio del ciclo"]
            case .cycleEnd: return ["cycle end time", "hora de finalizacion del ciclo"]
            case .timeZone: return ["cycle timezone", "zona horaria del ciclo"]
            case .recovery: return ["recovery score", "puntuacion de recuperacion"]
            case .rhr: return ["resting heart rate", "frecuencia cardiaca en reposo"]
            case .hrv: return ["heart rate variability", "variabilidad de la frecuencia cardiaca"]
            case .skinTemp: return ["skin temp", "temp. cutanea", "temperatura cutanea"]
            case .spo2: return ["blood oxygen", "oxigeno en sangre"]
            case .dayStrain: return ["day strain", "esfuerzo del dia"]
            case .energy: return ["energy burned", "energia quemada"]
            case .maxHR: return ["max hr", "fc max"]
            case .avgHR: return ["average hr", "fc promedio", "fc media"]
            case .sleepOnset: return ["sleep onset", "inicio del sueno"]
            case .wakeOnset: return ["wake onset", "inicio de la vigilia"]
            case .performance: return ["sleep performance", "calificacion del sueno", "rendimiento del sueno"]
            case .respRate: return ["respiratory rate", "frecuencia respiratoria"]
            case .asleep: return ["asleep duration", "duracion del sueno"]
            case .inBed: return ["in bed duration", "tiempo en la cama"]
            case .light: return ["light sleep duration", "sueno ligero"]
            case .deep: return ["deep (sws) duration", "sueno profundo"]
            case .rem: return ["rem duration", "sueno rem"]
            case .awake: return ["awake duration", "despierto"]
            case .need: return ["sleep need", "sueno necesario"]
            case .debt: return ["sleep debt", "deuda de sueno"]
            case .efficiency: return ["sleep efficiency", "eficiencia del sueno"]
            case .consistency: return ["sleep consistency", "regularidad del sueno", "consistencia del sueno"]
            case .nap: return ["=nap", "=siesta"]
            case .workoutStart: return ["workout start time", "hora de inicio del entrenamiento"]
            case .workoutEnd: return ["workout end time", "hora de finalizacion del entrenamiento"]
            case .activity: return ["activity name", "nombre de la actividad"]
            case .activityStrain: return ["activity strain", "esfuerzo de actividad", "esfuerzo de la actividad"]
            case .zone1: return ["hr zone 1", "zona fc 1"]
            case .zone2: return ["hr zone 2", "zona fc 2"]
            case .zone3: return ["hr zone 3", "zona fc 3"]
            case .zone4: return ["hr zone 4", "zona fc 4"]
            case .zone5: return ["hr zone 5", "zona fc 5"]
            case .distance: return ["distance (meters)", "distancia (metros)", "distancia (m)"]
            case .question: return ["question text", "texto de la pregunta"]
            case .answer: return ["answered yes", "respondio"]
            }
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Table {
        let header: [String]
        let rows: [[String]]
        var index: [Col: Int] = [:]

        init(_ rows: [[String]]) {
            header = (rows.first ?? []).map(WhoopExport.normalize)
            self.rows = Array(rows.dropFirst())
            for c in Col.allCases {
                for n in c.needles {
                    let hit: Int?
                    if n.hasPrefix("=") {
                        let exact = String(n.dropFirst())
                        hit = header.firstIndex { $0 == exact }
                    } else {
                        hit = header.firstIndex { $0.contains(n) }
                    }
                    if let hit {
                        index[c] = hit
                        break
                    }
                }
            }
        }

        func has(_ c: Col) -> Bool { index[c] != nil }

        func text(_ row: [String], _ c: Col) -> String? {
            guard let i = index[c], i < row.count else { return nil }
            let t = row[i].trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }

        func num(_ row: [String], _ c: Col) -> Double? {
            guard let t = text(row, c) else { return nil }
            let v = Double(t.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "."))
            return v.flatMap { $0.isFinite ? $0 : nil }
        }

        func bool(_ row: [String], _ c: Col) -> Bool? {
            guard let t = text(row, c).map(WhoopExport.normalize) else { return nil }
            if ["true", "yes", "si", "1", "verdadero"].contains(t) { return true }
            if ["false", "no", "0", "falso"].contains(t) { return false }
            return nil
        }

        func date(_ row: [String], _ c: Col) -> Date? {
            guard let t = text(row, c) else { return nil }
            return WhoopExport.parseDate(t, zone: text(row, .timeZone).flatMap(WhoopExport.zone))
        }
    }

    /// Recognises a WHOOP CSV by its header.
    public static func kind(of text: String) -> Kind? {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        return kind(Table(CSV.parse(String(firstLine))))
    }

    static func kind(_ t: Table) -> Kind? {
        if t.has(.question) && t.has(.answer) { return .journal }
        if t.has(.workoutStart) { return .workouts }
        if t.has(.recovery) || t.has(.hrv) || t.has(.dayStrain) { return .cycles }
        if t.has(.sleepOnset) && t.has(.wakeOnset) { return .sleeps }
        return nil
    }

    /// "UTC+01:00", "UTC-05:30", "+0200" or an IANA name.
    static func zone(_ s: String) -> TimeZone? {
        if s.contains("/"), let tz = TimeZone(identifier: s) { return tz }
        let t = s.uppercased().replacingOccurrences(of: "UTC", with: "").replacingOccurrences(of: "GMT", with: "")
            .trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return TimeZone(secondsFromGMT: 0) }
        guard let sign = t.first, sign == "+" || sign == "-" else { return nil }
        let parts = t.dropFirst().split(separator: ":").map(String.init)
        let h: Int, m: Int
        if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) {
            (h, m) = (a, b)
        } else if parts.count == 1, let v = Int(parts[0]) {
            (h, m) = parts[0].count > 2 ? (v / 100, v % 100) : (v, 0)
        } else {
            return nil
        }
        return TimeZone(secondsFromGMT: (h * 3600 + m * 60) * (sign == "-" ? -1 : 1))
    }

    static func parseDate(_ s: String, zone: TimeZone? = nil) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "MM/dd/yyyy HH:mm", "yyyy-MM-dd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if let zone { f.timeZone = zone }
        let t = s.trimmingCharacters(in: .whitespaces)
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    // MARK: Reading

    public static func read(_ files: [File], calendar: Calendar = .current) -> Bundle {
        var out = Bundle()
        var days: [String: DaySummary] = [:]
        var naps: [String: Double] = [:]
        var reports: [Int: FileReport] = [:]
        // Cycles first so sleeps only fill what they lack, whatever order the files came in.
        let tables = files.enumerated().map { (i: $0.offset, file: $0.element, table: Table(CSV.parse($0.element.text))) }
        for (i, file, t) in tables.sorted(by: { order(kind($0.table)) < order(kind($1.table)) }) {
            let k = kind(t)
            var used = 0
            switch k {
            case .cycles?, .sleeps?:
                for row in t.rows {
                    if t.bool(row, .nap) == true {
                        if let d = dayKey(t, row, calendar: calendar), let m = t.num(row, .asleep) {
                            naps[d, default: 0] += m
                            used += 1
                        }
                        continue
                    }
                    guard let s = day(t, row, calendar: calendar) else { continue }
                    days[s.day] = merge(days[s.day], s)
                    used += 1
                }
            case .workouts?:
                for row in t.rows {
                    guard let w = workout(t, row) else { continue }
                    out.workouts.append(w)
                    used += 1
                }
            case .journal?:
                for row in t.rows {
                    guard let q = t.text(row, .question), let yes = t.bool(row, .answer),
                          let day = dayKey(t, row, calendar: calendar) else { continue }
                    out.journal.append(JournalEntry(day: day, key: journalKey(q), value: yes ? 1 : 0))
                    used += 1
                }
            case nil:
                break
            }
            reports[i] = FileReport(name: file.name, kind: k, rows: t.rows.count, used: used)
        }
        for (d, m) in naps where days[d] != nil { days[d]?.napMinutes = m }
        out.days = days.values.sorted { $0.day < $1.day }
        // The same workout in two files (or twice in one) is kept once.
        var seen = Set<Int>()
        out.workouts = out.workouts.sorted { $0.start < $1.start }.filter { seen.insert($0.start).inserted }
        for i in out.days.indices {
            guard let a = out.days[i].cycleStart else { continue }
            let b = out.days[i].cycleEnd ?? Int.max
            out.days[i].workoutCount = out.workouts.filter { $0.end > a && $0.start < b }.count
        }
        out.files = reports.keys.sorted().compactMap { reports[$0] }
        return out
    }

    // MARK: Storing

    public struct Stored: Equatable, Sendable {
        public var days = 0
        public var workoutsNew = 0
        public var workoutsLinked = 0
        public var workoutsKnown = 0
        public var journal = 0

        public init() {}
    }

    /// Saves an import. Running it again with the same files changes nothing: days are refreshed (fields
    /// only an earlier file had are kept), workouts already imported are skipped, workouts the app
    /// already had are linked, and journal answers never overwrite what was logged in Pulso.
    public static func store(_ b: Bundle, in db: PulsoDatabase) throws -> Stored {
        var s = Stored()
        let known = Dictionary(try db.importedDays().map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for d in b.days {
            try db.saveImported(known[d.day].map { merge(d, $0) } ?? d)
            s.days += 1
        }
        for w in b.workouts {
            let nearby = try db.workouts(from: w.start - 3 * 3600, to: w.end + 3 * 3600)
            switch WorkoutMerge.decide(w, service: "whoop", existing: nearby) {
            case .duplicate:
                s.workoutsKnown += 1
            case .insert:
                try db.save(w)
                s.workoutsNew += 1
            case .link(let i):
                try db.save(WorkoutMerge.link(w, into: nearby[i], service: "whoop"))
                s.workoutsLinked += 1
            case .replaceAuto(let i):
                if let id = nearby[i].id { try db.deleteWorkout(id: id) }
                try db.save(w)
                s.workoutsNew += 1
            }
        }
        var logged: [String: [String: Double]] = [:]
        for e in b.journal {
            var day = try logged[e.day] ?? db.journal(day: e.day)
            guard day[e.key] == nil else { continue }
            try db.setJournal(day: e.day, key: e.key, value: e.value)
            day[e.key] = e.value
            logged[e.day] = day
            s.journal += 1
        }
        return s
    }

    static func order(_ k: Kind?) -> Int {
        switch k {
        case .cycles?: return 0
        case .sleeps?: return 1
        case .workouts?: return 2
        case .journal?: return 3
        case nil: return 4
        }
    }

    /// The Pulso day a row belongs to: the date of waking up, or the cycle start + 12 h.
    static func dayKey(_ t: Table, _ row: [String], calendar: Calendar) -> String? {
        if let w = t.date(row, .wakeOnset) { return DayKey.string(w, calendar: calendar) }
        if let c = t.date(row, .cycleStart), let mid = calendar.date(byAdding: .hour, value: 12, to: c) {
            return DayKey.string(mid, calendar: calendar)
        }
        return nil
    }

    static func day(_ t: Table, _ row: [String], calendar: Calendar) -> DaySummary? {
        guard let key = dayKey(t, row, calendar: calendar) else { return nil }
        var s = DaySummary(day: key)
        s.source = "whoop"
        s.calibrating = false
        s.recovery = t.num(row, .recovery)
        s.rhr = t.num(row, .rhr)
        s.hrv = t.num(row, .hrv)
        s.skinTemp = t.num(row, .skinTemp)
        s.spo2 = t.num(row, .spo2)
        s.strain = t.num(row, .dayStrain)
        s.kcal = t.num(row, .energy)
        s.maxHR = t.num(row, .maxHR)
        s.avgHR = t.num(row, .avgHR)
        s.respRate = t.num(row, .respRate)
        s.sleepMinutes = t.num(row, .asleep)
        s.inBedMinutes = t.num(row, .inBed)
        s.lightMinutes = t.num(row, .light)
        s.deepMinutes = t.num(row, .deep)
        s.remMinutes = t.num(row, .rem)
        s.awakeMinutes = t.num(row, .awake)
        s.sleepNeedMinutes = t.num(row, .need)
        s.sleepDebtMinutes = t.num(row, .debt)
        s.sleepPerformance = t.num(row, .performance).map { $0 / 100 }
        s.sleepEfficiency = t.num(row, .efficiency).map { $0 / 100 }
        s.sleepConsistency = t.num(row, .consistency)
        s.sleepStart = t.date(row, .sleepOnset).map { Int($0.timeIntervalSince1970) }
        s.sleepEnd = t.date(row, .wakeOnset).map { Int($0.timeIntervalSince1970) }
        s.cycleStart = t.date(row, .cycleStart).map { Int($0.timeIntervalSince1970) }
        s.cycleEnd = t.date(row, .cycleEnd).map { Int($0.timeIntervalSince1970) }
        guard s.hrv != nil || s.rhr != nil || s.strain != nil || s.sleepMinutes != nil else { return nil }
        return s
    }

    /// Fields `a` already has win; `b` only fills its gaps.
    public static func merge(_ a: DaySummary?, _ b: DaySummary) -> DaySummary {
        guard var m = a else { return b }
        func fill<T>(_ k: WritableKeyPath<DaySummary, T?>) {
            if m[keyPath: k] == nil { m[keyPath: k] = b[keyPath: k] }
        }
        fill(\.recovery); fill(\.rhr); fill(\.hrv); fill(\.skinTemp); fill(\.spo2); fill(\.strain); fill(\.kcal)
        fill(\.maxHR); fill(\.avgHR); fill(\.respRate); fill(\.sleepMinutes); fill(\.inBedMinutes); fill(\.lightMinutes)
        fill(\.deepMinutes); fill(\.remMinutes); fill(\.awakeMinutes); fill(\.sleepNeedMinutes); fill(\.sleepDebtMinutes)
        fill(\.sleepPerformance); fill(\.sleepEfficiency); fill(\.sleepConsistency); fill(\.sleepStart); fill(\.sleepEnd)
        fill(\.cycleStart); fill(\.cycleEnd); fill(\.napMinutes)
        return m
    }

    static func workout(_ t: Table, _ row: [String]) -> Workout? {
        guard let s = t.date(row, .workoutStart), let e = t.date(row, .workoutEnd), e > s else { return nil }
        let start = Int(s.timeIntervalSince1970), end = Int(e.timeIntervalSince1970)
        let name = t.text(row, .activity) ?? "Actividad"
        let sport = sportName(name)
        let minutes = Double(end - start) / 60
        let zones: [Col] = [.zone1, .zone2, .zone3, .zone4, .zone5]
        var w = Workout(start: start, end: end, sport: sport, source: .whoop,
                        strain: t.num(row, .activityStrain) ?? 0, avgHR: t.num(row, .avgHR) ?? 0,
                        maxHR: t.num(row, .maxHR) ?? 0, kcal: t.num(row, .energy) ?? 0,
                        zoneMinutes: zones.map { (t.num(row, $0) ?? 0) / 100 * minutes },
                        notes: normalize(sport) == normalize(name) ? "" : "Importado: \(name)", externalApp: "Importación",
                        distanceMeters: t.num(row, .distance))
        w.setExternalID(String(start), for: "whoop")
        return w
    }

    /// WHOOP activity names (English and Spanish) → Pulso's sport names.
    static func sportName(_ name: String) -> String {
        let n = normalize(name)
        let table: [(String, [String])] = [
            ("Spinning", ["spin", "indoor cycling", "giro"]),
            ("Bici de montaña", ["mountain biking", "bici de montana", "mtb"]),
            ("Cinta de correr", ["treadmill", "cinta"]),
            ("Atletismo", ["track & field", "atletismo"]),
            ("Carrera", ["running", "carrera", "correr"]),
            ("Ciclismo", ["cycling", "ciclismo", "bicicleta", "assault bike"]),
            ("Caminata", ["walking", "caminar", "caminata", "paseo"]),
            ("Montañismo", ["mountaineering", "montanismo"]),
            ("Senderismo", ["hiking", "senderismo", "rucking"]),
            ("Entrenamiento funcional", ["functional fitness", "entrenamiento funcional", "functional"]),
            ("Fuerza", ["weightlifting", "powerlifting", "strength", "levantamiento", "fuerza", "pesas"]),
            ("Comba", ["jump rope", "comba", "saltar"]),
            ("HIIT", ["hiit"]),
            ("Crossfit", ["crossfit"]),
            ("Waterpolo", ["water polo", "waterpolo"]),
            ("Natación", ["swimming", "natacion"]),
            ("Paddle surf", ["paddleboard", "paddle surf", "paddleboarding"]),
            ("Kayak / piragüismo", ["kayak", "piragu", "canoe", "piragua"]),
            ("Remo", ["rowing", "remo"]),
            ("Windsurf / kitesurf", ["kite", "windsurf"]),
            ("Surf", ["surf"]),
            ("Vela", ["sailing", "vela"]),
            ("Buceo", ["diving", "buceo"]),
            ("Yoga", ["yoga"]),
            ("Pilates", ["pilates"]),
            ("Barre", ["barre"]),
            ("Estiramientos", ["stretching", "estiramiento"]),
            ("Meditación", ["meditation", "meditacion", "breathwork"]),
            ("Elíptica", ["elliptical", "eliptica"]),
            ("Escaleras", ["stairmaster", "escaladora", "stair"]),
            ("Pádel", ["padel"]),
            ("Squash", ["squash", "racquetball"]),
            ("Bádminton", ["badminton"]),
            ("Pickleball", ["pickleball"]),
            ("Pimpón", ["ping pong", "table tennis", "tenis de mesa"]),
            ("Tenis", ["tennis", "tenis"]),
            ("Fútbol americano", ["football (american)", "american football", "futbol americano"]),
            ("Fútbol", ["soccer", "futbol"]),
            ("Baloncesto", ["basketball", "baloncesto"]),
            ("Voleibol", ["volleyball", "voleibol"]),
            ("Balonmano", ["handball", "balonmano"]),
            ("Rugby", ["rugby"]),
            ("Béisbol", ["baseball", "softball", "beisbol"]),
            ("Hockey", ["hockey", "lacrosse"]),
            ("Críquet", ["cricket"]),
            ("Escalada", ["climbing", "escalada", "bouldering"]),
            ("Esquí de fondo", ["cross country skiing", "esqui de fondo"]),
            ("Snowboard", ["snowboard"]),
            ("Esquí", ["skiing", "esqui"]),
            ("Patinaje", ["skating", "patinaje"]),
            ("Skate", ["skateboard"]),
            ("Kickboxing", ["kickboxing"]),
            ("Boxeo", ["boxing", "boxeo"]),
            ("Artes marciales", ["martial arts", "jiu jitsu", "artes marciales", "mma", "judo", "karate", "taekwondo"]),
            ("Lucha", ["wrestling", "lucha"]),
            ("Esgrima", ["fencing", "esgrima"]),
            ("Gimnasia", ["gymnastics", "gimnasia"]),
            ("Golf", ["golf"]),
            ("Equitación", ["horseback", "equitacion"]),
            ("Tiro con arco", ["archery"]),
            ("Bolos", ["bowling", "bolos"]),
            ("Zumba", ["zumba"]),
            ("Baile", ["dance", "baile", "bailar"]),
            ("Silla de ruedas", ["wheelchair"]),
            ("Tareas de casa", ["housework", "tareas domesticas"]),
            ("Jardinería", ["gardening", "jardineria"]),
            ("Videojuegos activos", ["gaming", "videojuego"]),
            ("Conducir", ["driving", "conducir", "motor racing"]),
            ("Moto", ["motocross", "moto"]),
            ("Sauna", ["sauna"]),
            ("Baño de hielo", ["ice bath", "bano de hielo", "cold plunge"]),
            ("Intimidad", ["sex", "intimidad"]),
        ]
        for (sport, keys) in table where keys.contains(where: { n.contains($0) }) { return sport }
        return "Actividad"
    }

    /// WHOOP journal questions that match Pulso's own habits; any other answer is kept under its question.
    static func journalKey(_ question: String) -> String {
        let q = normalize(question)
        let table: [(String, [String])] = [
            ("alcohol", ["alcohol"]),
            ("reading", ["lees", "leiste", "read"]),
            ("screens_bed", ["pantalla", "screen"]),
            ("late_meal", ["cerca de la hora de dormir", "close to bedtime", "before bed"]),
            ("magnesium", ["magnesio", "magnesium"]),
            ("meditation", ["medita"]),
            ("shared_bed", ["compartiste la cama", "share your bed", "shared your bed"]),
            ("sauna", ["sauna"]),
            ("sick", ["enfermo", "sick"]),
            ("travel", ["viaj", "travel"]),
            ("high_stress", ["estres", "stress"]),
        ]
        for (key, needles) in table where needles.contains(where: { q.contains($0) }) { return key }
        return "whoop:" + question.trimmingCharacters(in: .whitespaces)
    }
}

/// The original single-file entry point, kept for older callers: days from a cycles or sleep CSV.
public enum WhoopExportImporter {
    public static func parse(csv text: String, calendar: Calendar = .current) -> [DaySummary] {
        WhoopExport.read([.init(name: "export.csv", text: text)], calendar: calendar).days
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
