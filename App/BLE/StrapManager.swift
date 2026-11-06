import Foundation
import CoreBluetooth
import WhoopProtocol

enum StrapUUID {
    static let service = CBUUID(string: "FD4B0001-CCE1-4033-93CE-002D5875F58A")
    static let cmdWrite = CBUUID(string: "FD4B0002-CCE1-4033-93CE-002D5875F58A")
    static let cmdNotify = CBUUID(string: "FD4B0003-CCE1-4033-93CE-002D5875F58A")
    static let events = CBUUID(string: "FD4B0004-CCE1-4033-93CE-002D5875F58A")
    static let data = CBUUID(string: "FD4B0005-CCE1-4033-93CE-002D5875F58A")
    static let console = CBUUID(string: "FD4B0007-CCE1-4033-93CE-002D5875F58A")
    static let notifyChars: [CBUUID] = [cmdNotify, events, data, console]

    /// WHOOP 4.0 service, only used to recognise (and politely reject) a 4.0 during scanning.
    static let gen4Service = CBUUID(string: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6")

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInfoService = CBUUID(string: "180A")
    static let modelNumber = CBUUID(string: "2A24")
    static let serialNumber = CBUUID(string: "2A25")
    static let firmwareRevision = CBUUID(string: "2A26")
    static let hardwareRevision = CBUUID(string: "2A27")
}

enum StrapState: Equatable {
    case bluetoothOff
    case unauthorized
    case noStrap
    case scanning
    case connecting
    case pairing
    case pairingRefused
    case ready
    case syncing(records: Int)
    case unsupported(String)

    var isConnected: Bool {
        switch self {
        case .ready, .syncing: return true
        default: return false
        }
    }
}

/// How the session is opened after connecting. `standard` subscribes everything at once (NOOP style);
/// `sequential` follows OpenStrap Edge's documented order (600 ms after the bond, one subscription at a
/// time, 500 ms, GET_HELLO with retry, clock, GET_ADVERTISING_NAME). Pulso falls back automatically.
enum HandshakeMode: String, CaseIterable {
    case standard, sequential

    var label: String { self == .standard ? "Estándar" : "Secuencial (OpenStrap)" }
    var other: HandshakeMode { self == .standard ? .sequential : .standard }
}

/// A strap seen while scanning. Nothing connects until the user picks one.
struct DiscoveredStrap: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
}

struct StrapIdentity: Equatable {
    var name: String = ""
    var serial: String = ""
    var firmware: String = ""
    var hardware: String = ""
    var model: String = ""
    var isMG: Bool { hardware.hasPrefix("WS50") || model.uppercased() == "MG" }
}

/// Everything the strap reports, delivered on the main queue.
protocol StrapManagerDelegate: AnyObject {
    func strapStateChanged(_ state: StrapState)
    func strapIdentityChanged(_ identity: StrapIdentity)
    func strapBattery(percent: Double, charging: Bool?)
    func strapLive(heartRate: Int, rr: [Int], at date: Date)
    func strapEvent(_ event: StrapEvent)
    func strapSyncFinished(newRecords: Int, firstTs: Int?, lastTs: Int?, completed: Bool)
    func strapLog(_ line: String)
    /// Raw frame the app didn't route (ECG decoders / Laboratorio). Called on the BLE queue.
    func strapUnhandledFrame(_ frame: Frame)
    /// Straps found during a scan (main queue).
    func strapDiscovered(_ straps: [DiscoveredStrap])
}

/// CoreBluetooth engine for the WHOOP 5.0 / MG.
///
/// Session lifecycle (mirrors the official app, as documented by the open-source community):
/// connect → discover → write CLIENT_HELLO *with response* (this confirmed write triggers the
/// encrypted BLE bond) → subscribe the vendor notify characteristics (only after the bond — they
/// refuse unauthenticated subscriptions) → GET_HELLO → SET_CLOCK if the strap clock drifted
/// (an un-clocked strap discards data) → GET_BATTERY → historical offload with chunk ACKs.
final class StrapManager: NSObject {
    weak var delegate: StrapManagerDelegate?

    /// Persists a chunk of decoded seconds. Must throw if they were not stored: a chunk is only
    /// acknowledged (letting the strap free it) after this returns.
    var persist: (([HistorySample]) throws -> Void)?
    var persistUndecoded: (([Frame]) throws -> Void)?

    private let queue = DispatchQueue(label: "pulso.ble", qos: .userInitiated)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var deframers: [CBUUID: Deframer] = [:]
    private let commands = CommandBuilder(family: .gen5)

    private var bonded = false
    private var sessionStarted = false
    private var pendingSubscriptions = Set<CBUUID>()
    private var helloTimeout: DispatchWorkItem?
    private var sessionTimer: DispatchWorkItem?
    private var unsupportedLogged = false
    /// Time the strap's firmware alarm was last armed for on this link (avoids re-sending the same
    /// SET_ALARM_TIME on every schedule refresh).
    private var armedAlarm: Date?
    /// The alarm the app wants on the strap, kept across links (unlike `armedAlarm`): every new session arms it
    /// right after the clock, so a reconnect while iOS keeps the app suspended still gets the wake-up call.
    private var desiredAlarm: (date: Date, silent: Bool)?
    /// A SET_ALARM_TIME was sent and never cancelled. The strap may keep it across a disconnect, so a cancel asked
    /// for while unlinked goes out on the next link (the alarm is one-shot, so after firing this is just one
    /// harmless extra disable).
    private var strapMayHoldAlarm = false
    private var helloReceived = false
    private var helloRetried = false
    private var subscribeQueue: [CBUUID] = []
    private var subscriptionErrors = 0
    /// Automatic mode switches made since the app started (capped so it never loops).
    private var autoSwitches = 0

    private static let modeKey = "pulso.handshake.mode"
    private static let forcedKey = "pulso.handshake.forced"
    private static let workedKey = "pulso.handshake.worked"

    /// Mode used for the next session (forced > last that worked > current choice).
    private(set) var mode: HandshakeMode = HandshakeMode(rawValue: UserDefaults.standard.string(forKey: "pulso.handshake.forced") ?? "")
        ?? HandshakeMode(rawValue: UserDefaults.standard.string(forKey: "pulso.handshake.worked") ?? "")
        ?? HandshakeMode(rawValue: UserDefaults.standard.string(forKey: "pulso.handshake.mode") ?? "")
        ?? .standard

    var forcedMode: HandshakeMode? { HandshakeMode(rawValue: UserDefaults.standard.string(forKey: Self.forcedKey) ?? "") }
    var workedMode: HandshakeMode? { HandshakeMode(rawValue: UserDefaults.standard.string(forKey: Self.workedKey) ?? "") }
    private var negotiatedMTU = 0
    private var clockChecked = false

    private var offload: OffloadSession?
    private var offloadIdle: DispatchWorkItem?
    private var offloadRecords = 0
    private var offloadFirst: Int?
    private var offloadLast: Int?
    /// Corrupt (bad-CRC) frames seen on the data channel since the last chunk boundary of the running offload.
    /// HISTORY_END would still ack that chunk and let the strap free records we never stored.
    private var offloadBadCRC: [Frame] = []
    /// Offloads restarted on this link because a chunk had corrupt frames (reset on a clean chunk).
    private var crcRetries = 0
    static let maxCRCRetries = 2
    private var lastSyncAt: Date?
    private var lastSyncProgress = Date.distantPast
    /// Next automatic download while the link stays up (runs whenever the app is awake then).
    private var autoSync: DispatchWorkItem?
    /// Gap between automatic downloads on a link that stays connected all day.
    static let autoSyncInterval: TimeInterval = 30 * 60
    private var wantsLive = false
    /// A scan was requested before Bluetooth finished powering on.
    private var wantsScan = false
    private var liveBuffer: [HistorySample] = []
    /// When the vendor realtime stream is flowing, the standard 0x2A37 heart-rate notifications carry
    /// the same beats; forwarding both would double-count R-R intervals.
    private var lastVendorRealtime: Date?
    private var identity = StrapIdentity()
    private var discovered: [UUID: (peripheral: CBPeripheral, strap: DiscoveredStrap)] = [:]
    /// Stops the current scan after a while; replaced on every new scan so an old timer never cuts a new one.
    private var scanTimeout: DispatchWorkItem?

    /// Raw capture for the Laboratorio screen (accessed on the BLE queue).
    let recorder = FrameRecorder()

    private(set) var state: StrapState = .noStrap {
        didSet {
            guard state != oldValue else { return }
            let s = state
            DispatchQueue.main.async { self.delegate?.strapStateChanged(s) }
        }
    }

    private static let savedPeripheralKey = "pulso.strap.peripheral"
    private static let restoreID = "pulso.ble.central"

    var hasSavedStrap: Bool { UserDefaults.standard.string(forKey: Self.savedPeripheralKey) != nil }

    /// False in screenshot mode (simulator, no Bluetooth): nothing touches CoreBluetooth then.
    private let active = !AppMode.screenshots

    override init() {
        super.init()
        guard active else { return }
        central = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    // MARK: - Public API (any thread)

    /// Reconnects to the strap the user paired. Never scans and never touches another strap.
    func connect() {
        guard active else { return }
        queue.async { self.connectLocked() }
    }

    /// Looks for nearby straps and lists them. It does NOT connect: the user picks one with `choose`.
    func scan() {
        guard active else { return }
        queue.async {
            self.discovered.removeAll()
            self.publishDiscovered()
            self.startScan()
        }
    }

    func stopScan() {
        guard active else { return }
        queue.async {
            self.scanTimeout?.cancel()
            self.central.stopScan()
            if self.state == .scanning { self.restoreStateAfterScan() }
        }
    }

    /// After a scan: back to "ready" if still connected, reconnect to the paired strap, or idle.
    private func restoreStateAfterScan() {
        if bonded && sessionStarted, peripheral?.state == .connected {
            state = .ready
        } else if hasSavedStrap {
            state = .connecting
            connectLocked()
        } else {
            state = .noStrap
        }
    }

    /// Pairs with the strap the user picked from the scan list (forgetting any previous one).
    func choose(_ id: UUID) {
        guard active else { return }
        queue.async {
            guard let found = self.discovered[id] else { return }
            self.scanTimeout?.cancel()
            self.central.stopScan()
            UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
            if let p = self.peripheral, p.identifier != id { self.central.cancelPeripheralConnection(p) }
            self.resetSession()
            self.identity = StrapIdentity()
            self.identity.name = found.strap.name
            self.attach(found.peripheral)
            self.state = .connecting
            self.central.connect(found.peripheral, options: nil)
            self.log("Emparejando con \(found.strap.name)")
        }
    }

    private func publishDiscovered() {
        let list = discovered.values.map { $0.strap }.sorted { $0.rssi > $1.rssi }
        DispatchQueue.main.async { self.delegate?.strapDiscovered(list) }
    }

    func forget() {
        guard active else { return }
        queue.async {
            UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
            if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
            self.peripheral = nil
            self.resetSession()
            self.central.stopScan()
            self.state = .noStrap
        }
    }

    /// Pulls every banked second off the strap. `force` ignores the 10-minute floor.
    func sync(force: Bool = false) {
        guard active else { return }
        queue.async { self.startOffload(force: force) }
    }

    func setLive(_ on: Bool) {
        guard active else { return }
        queue.async {
            self.wantsLive = on
            if self.bonded, let p = self.peripheral, p.state == .connected, let hr = self.chars[StrapUUID.heartRateMeasurement] {
                p.setNotifyValue(on, for: hr)
            }
            guard self.bonded, self.sessionStarted else { return }
            self.send(self.commands.toggleRealtimeHR(on))
        }
    }

    func buzz(loops: UInt8 = 2) {
        guard active else { return }
        queue.async { self.send(self.commands.buzz(loops: loops)) }
    }

    /// Plays specific haptic waveform ids (Laboratorio tester).
    func haptic(effects: [UInt8], loops: UInt8) {
        guard active else { return }
        queue.async { self.send(self.commands.haptic(effects: effects, loops: loops)) }
    }

    func stopHaptics() {
        guard active else { return }
        queue.async { self.send(self.commands.stopHaptics()) }
    }

    /// Forces a handshake mode (nil = automatic) and reconnects to apply it.
    func setForcedMode(_ m: HandshakeMode?) {
        UserDefaults.standard.set(m?.rawValue, forKey: Self.forcedKey)
        queue.async {
            if let m { self.mode = m }
            self.log("Modo de conexión: \(m?.label ?? "automático")")
            if let p = self.peripheral, p.state == .connected { self.central.cancelPeripheralConnection(p) }
        }
    }

    /// Text block for the diagnostics report.
    func diagnostics(_ done: @escaping (String) -> Void) {
        queue.async {
            let lines = [
                "Estado: \(self.state)",
                "Modo de conexión: \(self.mode.label) (forzado: \(self.forcedMode?.label ?? "no"), funcionó: \(self.workedMode?.label ?? "aún ninguno"))",
                "Cambios automáticos de modo: \(self.autoSwitches)",
                "Emparejada: \(self.bonded) · sesión: \(self.sessionStarted) · hello: \(self.helloReceived)",
                "Errores de suscripción: \(self.subscriptionErrors)",
                "MTU de escritura: \(self.negotiatedMTU)",
                "Pulsera guardada: \(self.hasSavedStrap)",
                "Identidad: \(self.identity.name) · serie \(self.identity.serial) · fw \(self.identity.firmware) · hw \(self.identity.hardware) · modelo \(self.identity.model)",
                "Tramas por tipo: " + self.recorder.typeCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            ]
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async { done(text) }
        }
    }

    /// Starts / stops recording raw frames.
    func setCapture(_ on: Bool, all: Bool) {
        queue.async {
            self.recorder.isRecording = on
            self.recorder.recordAll = all
        }
    }

    /// Text dump of the capture and the per-type counters.
    func exportCapture(_ done: @escaping (String, [UInt8: Int]) -> Void) {
        queue.async {
            let text = self.recorder.export()
            let counts = self.recorder.typeCounts
            DispatchQueue.main.async { done(text, counts) }
        }
    }

    func clearCapture() {
        queue.async { self.recorder.clear() }
    }

    /// Arms the strap's own alarm (experimental on 5.0 firmware; the app also schedules a phone notification
    /// as a backup). `silent`: no vibration, only the Bluetooth event that wakes the app.
    func setAlarm(_ date: Date?, silent: Bool = false) {
        guard active else { return }
        queue.async {
            self.desiredAlarm = date.map { (date: $0, silent: silent) }
            guard self.bonded else { return }
            self.applyDesiredAlarm()
        }
    }

    /// Sends `desiredAlarm` to the strap (only when it changed on this link). Call on `queue` with the link bonded.
    private func applyDesiredAlarm() {
        if let want = desiredAlarm {
            // Its time went by while unlinked: nothing to arm.
            guard want.date > Date() else {
                desiredAlarm = nil
                return
            }
            if let armed = armedAlarm, abs(armed.timeIntervalSince(want.date)) < 1 { return }
            armedAlarm = want.date
            strapMayHoldAlarm = true
            send(commands.setAlarm(at: want.date, silent: want.silent))
        } else {
            guard armedAlarm != nil || strapMayHoldAlarm else { return }
            armedAlarm = nil
            strapMayHoldAlarm = false
            send(commands.disableAlarm())
        }
    }

    // MARK: - Connection

    private func connectLocked() {
        guard central.state == .poweredOn else { return }
        if state == .pairingRefused, let p = peripheral {
            // Retry the bond on a fresh link (didDisconnect re-arms the connection).
            state = .connecting
            central.cancelPeripheralConnection(p)
            return
        }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }
        if let idString = UserDefaults.standard.string(forKey: Self.savedPeripheralKey),
           let id = UUID(uuidString: idString),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(p)
            state = .connecting
            // A pending connect never times out: iOS completes it whenever the strap is in range,
            // even with the app in the background.
            central.connect(p, options: nil)
            return
        }
        // No paired strap: stay idle. Scanning only happens when the user asks for it, and even
        // then nothing connects until they pick a strap from the list.
        state = .noStrap
    }

    private func startScan() {
        guard central.state == .poweredOn else {
            wantsScan = true
            return
        }
        wantsScan = false
        state = .scanning
        // A strap already linked to this iPhone (bonded at system level, or connected by another app) stops
        // advertising: list it too so it can still be chosen.
        for p in central.retrieveConnectedPeripherals(withServices: [StrapUUID.service]) where discovered[p.identifier] == nil {
            discovered[p.identifier] = (p, DiscoveredStrap(id: p.identifier, name: Fmt.bandName(p.name ?? "Pulse Band"), rssi: -50))
            log("Pulsera ya conectada al iPhone: \(Fmt.bandName(p.name ?? "Pulse Band"))")
        }
        if !discovered.isEmpty { publishDiscovered() }
        central.scanForPeripherals(withServices: [StrapUUID.service, StrapUUID.gen4Service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .scanning else { return }
            self.central.stopScan()
            self.log("Búsqueda terminada")
            self.restoreStateAfterScan()
        }
        scanTimeout = timeout
        queue.asyncAfter(deadline: .now() + 45, execute: timeout)
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
    }

    /// Schedules `beginSession` so a reconnect can cancel a timer armed for the previous link.
    private func scheduleSession(after delay: Double) {
        sessionTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.beginSession() }
        sessionTimer = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// A strap that stays connected sends nothing on its own, so without this the data would wait on the
    /// strap until the app is opened. The timer only fires while the app is awake (foreground, live stream,
    /// alarms); strap events and live readings below cover the rest.
    private func scheduleAutoSync() {
        autoSync?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.startOffload(force: false) }
        autoSync = item
        queue.asyncAfter(deadline: .now() + Self.autoSyncInterval, execute: item)
    }

    private func resetSession() {
        autoSync?.cancel()
        autoSync = nil
        sessionTimer?.cancel()
        sessionTimer = nil
        armedAlarm = nil
        if !liveBuffer.isEmpty {
            _ = store(liveBuffer)
            liveBuffer.removeAll()
        }
        chars.removeAll()
        deframers.removeAll()
        bonded = false
        sessionStarted = false
        clockChecked = false
        pendingSubscriptions.removeAll()
        subscribeQueue.removeAll()
        subscriptionErrors = 0
        helloReceived = false
        helloRetried = false
        helloTimeout?.cancel()
        offloadIdle?.cancel()
        offload = nil
        offloadBadCRC.removeAll()
        crcRetries = 0
    }

    /// The current mode didn't get a working session: try the other one on a fresh link.
    private func handshakeFailed(_ reason: String) {
        log("Fallo en modo \(mode.label): \(reason)")
        guard forcedMode == nil, workedMode == nil, autoSwitches < 2, let p = peripheral else { return }
        autoSwitches += 1
        mode = mode.other
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        log("Probando el modo \(mode.label)…")
        central.cancelPeripheralConnection(p) // didDisconnect re-arms the connection
    }

    private func handshakeSucceeded() {
        guard workedMode != mode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: Self.workedKey)
        log("Conexión correcta en modo \(mode.label); lo recuerdo para la próxima vez")
    }

    private func log(_ s: String) {
        DispatchQueue.main.async { self.delegate?.strapLog(s) }
    }

    // MARK: - Writing

    private func send(_ frame: (seq: UInt8, bytes: [UInt8])?) {
        guard let frame else { return }
        write(frame.bytes)
    }

    private func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let c = chars[StrapUUID.cmdWrite], p.state == .connected else { return }
        // The strap only acts on acknowledged writes.
        p.writeValue(Data(bytes), for: c, type: .withResponse)
    }

    // MARK: - Session start (after bond)

    private func onBonded() {
        guard !bonded else { return }
        bonded = true
        guard let p = peripheral else { return }
        negotiatedMTU = p.maximumWriteValueLength(for: .withResponse)
        log("Pulsera emparejada (MTU \(negotiatedMTU)); suscribiendo canales en modo \(mode.label)")
        if mode == .sequential {
            // OpenStrap order: let the bond settle, then one subscription at a time.
            subscribeQueue = StrapUUID.notifyChars.filter { chars[$0] != nil }
            pendingSubscriptions = Set(subscribeQueue)
            queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.subscribeNext() }
            scheduleSession(after: 8)
            return
        }
        pendingSubscriptions = Set(StrapUUID.notifyChars.filter { chars[$0] != nil })
        for uuid in StrapUUID.notifyChars {
            if let c = chars[uuid] { p.setNotifyValue(true, for: c) }
        }
        subscribeStandardChars(p)
        // Continue even if a subscription confirmation never arrives.
        scheduleSession(after: 2.0)
    }

    /// Next vendor channel in sequential mode; standard GATT services come after them.
    private func subscribeNext() {
        guard let p = peripheral, p.state == .connected else { return }
        guard !subscribeQueue.isEmpty else {
            subscribeStandardChars(p)
            scheduleSession(after: 0.5)
            return
        }
        let uuid = subscribeQueue.removeFirst()
        if let c = chars[uuid] { p.setNotifyValue(true, for: c) } else { subscribeNext() }
    }

    private func subscribeStandardChars(_ p: CBPeripheral) {
        // The standard pulse only while something wants it: a strap with heart-rate broadcast on would otherwise
        // notify every second all day long.
        if wantsLive, let hr = chars[StrapUUID.heartRateMeasurement] { p.setNotifyValue(true, for: hr) }
        if let b = chars[StrapUUID.batteryLevel] {
            if b.properties.contains(.notify) { p.setNotifyValue(true, for: b) }
            p.readValue(for: b)
        }
        for uuid in [StrapUUID.serialNumber, StrapUUID.firmwareRevision, StrapUUID.hardwareRevision, StrapUUID.modelNumber] {
            if let c = chars[uuid] { p.readValue(for: c) }
        }
    }

    private func beginSession() {
        guard bonded, !sessionStarted else { return }
        sessionStarted = true
        state = .ready
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.send(self.commands.getHello())
            self.armHelloTimeout()
        }
    }

    private func armHelloTimeout() {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.helloReceived else { return }
            if !self.helloRetried {
                self.helloRetried = true
                self.log("Sin respuesta al saludo; lo repito")
                self.send(self.commands.getHello())
                self.armHelloTimeout()
                return
            }
            // No hello at all: set the clock anyway so the strap keeps banking data, and if this mode
            // never got a reply (nor subscriptions), try the other one.
            self.ensureClock(strapUnix: nil)
            if self.subscriptionErrors > 0 || self.recorder.typeCounts.isEmpty {
                self.handshakeFailed("la pulsera no responde")
            }
        }
        helloTimeout = timeout
        queue.asyncAfter(deadline: .now() + 4, execute: timeout)
    }

    private func ensureClock(strapUnix: UInt32?) {
        guard !clockChecked else { return }
        clockChecked = true
        helloTimeout?.cancel()
        let now = Date().timeIntervalSince1970
        if let s = strapUnix, abs(Double(s) - now) < 2 {
            log("Reloj de la pulsera correcto")
        } else {
            send(commands.setClock(Date()))
            log("Reloj de la pulsera ajustado")
        }
        send(commands.getBattery())
        // The strap's alarm is one-shot and the app may be suspended by now: re-arm it here, once the clock is right.
        applyDesiredAlarm()
        if mode == .sequential { send(commands.getAdvertisingName()) }
        if wantsLive { send(commands.toggleRealtimeHR(true)) }
        queue.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.startOffload(force: true) }
    }

    // MARK: - Historical offload

    private func startOffload(force: Bool) {
        guard bonded, sessionStarted, offload == nil else { return }
        if !force, let last = lastSyncAt, Date().timeIntervalSince(last) < 600 { return }
        offload = OffloadSession()
        offloadRecords = 0
        offloadFirst = nil
        offloadLast = nil
        offloadBadCRC.removeAll()
        state = .syncing(records: 0)
        log("Descargando historial…")
        // A battery reading with every download feeds the battery log (Dispositivo → duración de la carga).
        send(commands.getBattery())
        // NOOP / OpenStrap: the 5.0 asks for the data range before the history request (read-only).
        send(commands.getDataRange())
        send(commands.sendHistoricalData())
        armOffloadIdle()
    }

    private func armOffloadIdle() {
        offloadIdle?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.offload != nil else { return }
            self.log("La pulsera dejó de enviar; cierro la descarga")
            self.send(self.commands.abortHistorical())
            self.finishOffload(completed: true)
        }
        offloadIdle = item
        queue.asyncAfter(deadline: .now() + 10, execute: item)
    }

    /// Stores a chunk. `corrupt` are bad-CRC frames kept raw (in undecoded_records) so their bytes survive.
    /// Returns false when anything could not be stored: the caller must not ack then.
    private func store(_ samples: [HistorySample], undecoded: [Frame] = [], corrupt: [Frame] = []) -> Bool {
        // No persister yet means nothing would be saved: never let an ack free the strap's copy.
        guard let persist, let persistUndecoded else {
            log("Almacenamiento no disponible: no confirmo el bloque")
            return false
        }
        do {
            if !undecoded.isEmpty || !corrupt.isEmpty {
                try persistUndecoded(undecoded + corrupt)
                if !undecoded.isEmpty {
                    log("\(undecoded.count) registros en un formato desconocido: guardados sin decodificar")
                }
            }
            guard !samples.isEmpty else { return true }
            try persist(samples)
            guard offload != nil else { return true }
            offloadRecords += samples.count
            let ts = samples.map { Int($0.unix) }
            offloadFirst = min(offloadFirst ?? Int.max, ts.min() ?? Int.max)
            offloadLast = max(offloadLast ?? 0, ts.max() ?? 0)
            return true
        } catch {
            log("No se pudo guardar un bloque: \(error)")
            return false
        }
    }

    private func handleOffload(_ frame: Frame) {
        guard let session = offload else { return }
        armOffloadIdle()
        guard let step = session.handle(frame) else { return }
        switch step {
        case .chunk(let samples, let undecoded, let token, _):
            let corrupt = offloadBadCRC
            offloadBadCRC.removeAll()
            if !corrupt.isEmpty && crcRetries < Self.maxCRCRetries {
                // Records were lost to corruption: keep what did arrive (re-sending it later is an upsert),
                // don't ack, and ask again so the strap re-sends the whole chunk.
                crcRetries += 1
                _ = store(samples, undecoded: undecoded, corrupt: corrupt)
                log("\(corrupt.count) tramas dañadas en un bloque: no lo confirmo y vuelvo a pedirlo (intento \(crcRetries) de \(Self.maxCRCRetries))")
                send(commands.abortHistorical())
                finishOffload(completed: false)
                queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startOffload(force: true) }
                return
            }
            if !corrupt.isEmpty {
                // Retries exhausted: keep the corrupt frames' raw bytes and ack anyway, or the strap stays blocked
                // on this chunk forever.
                log("\(corrupt.count) tramas dañadas tras \(Self.maxCRCRetries) reintentos: guardadas sin decodificar y confirmo el bloque")
            }
            // A clean chunk, or one given up on: the next corrupt chunk gets its own retries.
            crcRetries = 0
            if store(samples, undecoded: undecoded, corrupt: corrupt) {
                send(commands.historyAck(token: token))
                // Each state change redraws every visible screen: chunks arrive many times a second.
                if Date().timeIntervalSince(lastSyncProgress) >= 1 {
                    lastSyncProgress = Date()
                    state = .syncing(records: offloadRecords)
                }
            } else {
                send(commands.abortHistorical())
                finishOffload(completed: false)
            }
        case .complete(let pending, let undecoded):
            // Nothing is acked here, so corrupt frames since the last chunk are just kept raw.
            let corrupt = offloadBadCRC
            offloadBadCRC.removeAll()
            finishOffload(completed: store(pending, undecoded: undecoded, corrupt: corrupt))
        }
    }

    private func finishOffload(completed: Bool) {
        offloadIdle?.cancel()
        offload = nil
        offloadBadCRC.removeAll()
        if completed { lastSyncAt = Date() }
        if bonded { state = .ready }
        scheduleAutoSync()
        let n = offloadRecords, a = offloadFirst, b = offloadLast
        log(completed ? "Descarga terminada: \(n) segundos nuevos" : "Descarga interrumpida: \(n) segundos guardados; el resto se pedirá de nuevo")
        DispatchQueue.main.async { self.delegate?.strapSyncFinished(newRecords: n, firstTs: a, lastTs: b, completed: completed) }
    }

    // MARK: - Frame routing

    private func route(_ frame: Frame, channel: CBUUID) {
        let message = StrapMessage.decode(frame)
        var handled = frame.crcOK
        if case .ignored = message { handled = false }
        recorder.record(frame, channel: channel.uuidString.prefix(8).lowercased(), handled: handled)
        guard frame.crcOK else {
            // A corrupt frame on the data channel mid-download may be a history record: remember it so its
            // chunk isn't acked blindly. Live-stream frames (a type byte that still reads as realtime) don't count.
            let liveType = frame.canonicalType.map { [PacketType.realtimeData, .realtimeRawData, .realtimeImuStream].contains($0) } ?? false
            if offload != nil, channel == StrapUUID.data, !liveType {
                offloadBadCRC.append(frame)
            }
            return
        }
        if !handled {
            delegate?.strapUnhandledFrame(frame)
            return
        }
        switch message {
        case .history(let sample):
            if !helloReceived { handshakeSucceeded() }
            if offload != nil {
                handleOffload(frame)
            } else {
                // Some straps also stream per-second records live (a persistent setting the official
                // app may have enabled). They're the same layout, so keep them.
                liveBuffer.append(sample)
                if liveBuffer.count >= 60 {
                    _ = store(liveBuffer)
                    liveBuffer.removeAll()
                }
            }
        case .otherHistory:
            handleOffload(frame)
        case .metadata:
            handleOffload(frame)
        case .realtime(let r):
            guard r.valid else { return }
            lastVendorRealtime = Date()
            // The live stream keeps the app awake (night, workouts): download now and then on the way.
            if let last = lastSyncAt, Date().timeIntervalSince(last) > Self.autoSyncInterval { startOffload(force: false) }
            let hr = Int(r.heartRate), rr = r.rr.map { Int($0) }
            DispatchQueue.main.async { self.delegate?.strapLive(heartRate: hr, rr: rr, at: Date()) }
        case .event(let e):
            DispatchQueue.main.async { self.delegate?.strapEvent(e) }
            if let pct = e.batteryPercent {
                DispatchQueue.main.async { self.delegate?.strapBattery(percent: pct, charging: e.charging) }
            }
            // Background opportunity: any strap event wakes us; use it to keep data flowing.
            startOffload(force: false)
        case .response(let r):
            handleResponse(r)
        case .ignored:
            break
        }
    }

    private func handleResponse(_ r: CommandResponse) {
        switch r.cmd {
        case Opcode.getHello:
            if r.status == .pending { return }
            helloReceived = true
            handshakeSucceeded()
            if let h = HelloInfo.decode(r) {
                if !h.serial.isEmpty { identity.serial = h.serial }
                if !h.firmware.isEmpty { identity.firmware = h.firmware }
                let id = identity
                DispatchQueue.main.async { self.delegate?.strapIdentityChanged(id) }
                if let b = h.batteryPercent {
                    DispatchQueue.main.async { self.delegate?.strapBattery(percent: Double(b), charging: h.charging) }
                }
                ensureClock(strapUnix: h.strapUnix)
            } else {
                ensureClock(strapUnix: nil)
            }
        case Opcode.getBatteryLevel:
            if let pct = r.batteryPercent {
                DispatchQueue.main.async { self.delegate?.strapBattery(percent: pct, charging: nil) }
            }
        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension StrapManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let p = peripheral, p.state == .connected {
                p.discoverServices(nil)
            } else if wantsScan {
                startScan()
            } else if hasSavedStrap {
                connectLocked()
            } else {
                state = .noStrap
            }
        case .unauthorized:
            state = .unauthorized
        case .poweredOff, .resetting:
            resetSession()
            state = .bluetoothOff
        default:
            state = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = restored.first {
            attach(p)
            log("Sesión Bluetooth restaurada por iOS")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        if services.contains(StrapUUID.gen4Service) && !services.contains(StrapUUID.service) {
            // Leaving `.scanning` here would orphan the scan (its stop paths check that state).
            if !unsupportedLogged {
                unsupportedLogged = true
                log("Se ha encontrado una pulsera de generación anterior: Pulso necesita una Pulse Band 5.0 / MG, la ignoro")
            }
            return
        }
        let name = Fmt.bandName((advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Pulse Band")
        let isNew = discovered[peripheral.identifier] == nil
        discovered[peripheral.identifier] = (peripheral, DiscoveredStrap(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        if isNew { log("Pulsera encontrada: \(name) (no se conecta hasta que la elijas)") }
        publishDiscovered()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        resetSession()
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.savedPeripheralKey)
        state = .pairing
        log("Conectado; descubriendo servicios")
        peripheral.discoverServices([StrapUUID.service, StrapUUID.heartRateService, StrapUUID.batteryService, StrapUUID.deviceInfoService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Fallo al conectar: \(error?.localizedDescription ?? "desconocido")")
        resetSession()
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let wasSyncing = offload != nil
        resetSession()
        if wasSyncing { finishOffload(completed: false) }
        log("Desconectado\(error.map { ": \($0.localizedDescription)" } ?? "")")
        guard hasSavedStrap, self.peripheral?.identifier == peripheral.identifier else {
            // A strap being replaced (or forgotten) went away: only idle if nothing else is in progress.
            if !hasSavedStrap && self.peripheral == nil { state = .noStrap }
            return
        }
        if state != .pairingRefused { state = .connecting }
        // Re-arm a pending connection: iOS will reconnect when the strap comes back in range.
        central.connect(peripheral, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension StrapManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            log("Error descubriendo servicios: \(error?.localizedDescription ?? "")")
            return
        }
        if !services.contains(where: { $0.uuid == StrapUUID.service }) {
            if services.contains(where: { $0.uuid == StrapUUID.gen4Service }) {
                state = .unsupported("Pulso necesita una Pulse Band 5.0 o MG. La pulsera encontrada es de una generación anterior.")
            }
        }
        for s in services {
            switch s.uuid {
            case StrapUUID.service:
                peripheral.discoverCharacteristics([StrapUUID.cmdWrite] + StrapUUID.notifyChars, for: s)
            case StrapUUID.heartRateService:
                peripheral.discoverCharacteristics([StrapUUID.heartRateMeasurement], for: s)
            case StrapUUID.batteryService:
                peripheral.discoverCharacteristics([StrapUUID.batteryLevel], for: s)
            case StrapUUID.deviceInfoService:
                peripheral.discoverCharacteristics([StrapUUID.serialNumber, StrapUUID.firmwareRevision,
                                                    StrapUUID.hardwareRevision, StrapUUID.modelNumber], for: s)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let list = service.characteristics else { return }
        for c in list {
            chars[c.uuid] = c
            if StrapUUID.notifyChars.contains(c.uuid) {
                deframers[c.uuid] = Deframer(family: .gen5)
            }
        }
        // Standard services discovered after the bond would otherwise never be read / subscribed.
        if bonded && service.uuid != StrapUUID.service { subscribeStandardChars(peripheral) }
        if service.uuid == StrapUUID.service, let cmd = chars[StrapUUID.cmdWrite] {
            // The confirmed CLIENT_HELLO write is what makes iOS run the (just-works) bond.
            log("Enviando saludo de emparejamiento")
            peripheral.writeValue(Data(CommandBuilder.gen5ClientHello), for: cmd, type: .withResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == StrapUUID.cmdWrite else { return }
        if let error {
            let ns = error as NSError
            let insufficient = ns.domain == CBATTErrorDomain &&
                (ns.code == CBATTError.Code.insufficientAuthentication.rawValue || ns.code == CBATTError.Code.insufficientEncryption.rawValue)
            if !bonded {
                if insufficient {
                    state = .pairingRefused
                    log("La pulsera rechaza el emparejamiento (probablemente sigue vinculada a la app de su fabricante)")
                    handshakeFailed("emparejamiento rechazado")
                } else {
                    log("Escritura fallida: \(error.localizedDescription)")
                }
                return
            }
            log("Escritura rechazada tras el emparejamiento: \(error.localizedDescription)")
            if insufficient, let p = self.peripheral {
                // The bond was lost mid-session: start over from discovery so the hello write re-bonds.
                resetSession()
                state = .pairing
                p.discoverServices([StrapUUID.service, StrapUUID.heartRateService, StrapUUID.batteryService, StrapUUID.deviceInfoService])
            }
            return
        }
        if !bonded { onBonded() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            subscriptionErrors += 1
            log("Suscripción \(characteristic.uuid.uuidString) falló: \(error.localizedDescription)")
        }
        let wasPending = pendingSubscriptions.remove(characteristic.uuid) != nil
        if mode == .sequential {
            if wasPending { queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.subscribeNext() } }
            return
        }
        if bonded && pendingSubscriptions.isEmpty { beginSession() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let bytes = [UInt8](value)
        switch characteristic.uuid {
        case StrapUUID.heartRateMeasurement:
            if let last = lastVendorRealtime, Date().timeIntervalSince(last) < 3 { return }
            if let m = StandardHRMeasurement.decode(bytes) {
                DispatchQueue.main.async { self.delegate?.strapLive(heartRate: m.heartRate, rr: m.rr, at: Date()) }
            }
        case StrapUUID.batteryLevel:
            if let pct = bytes.first, pct <= 100 {
                DispatchQueue.main.async { self.delegate?.strapBattery(percent: Double(pct), charging: nil) }
            }
        case StrapUUID.serialNumber, StrapUUID.firmwareRevision, StrapUUID.hardwareRevision, StrapUUID.modelNumber:
            let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            switch characteristic.uuid {
            case StrapUUID.serialNumber: identity.serial = text
            case StrapUUID.firmwareRevision: identity.firmware = text
            case StrapUUID.hardwareRevision: identity.hardware = text
            default: identity.model = text
            }
            let id = identity
            DispatchQueue.main.async { self.delegate?.strapIdentityChanged(id) }
        default:
            guard let deframer = deframers[characteristic.uuid] else { return }
            for frame in deframer.push(bytes) {
                route(frame, channel: characteristic.uuid)
            }
        }
    }
}
