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
    func strapSyncFinished(newRecords: Int, firstTs: Int?, lastTs: Int?)
    func strapLog(_ line: String)
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
    private var clockChecked = false

    private var offload: OffloadSession?
    private var offloadIdle: DispatchWorkItem?
    private var offloadRecords = 0
    private var offloadFirst: Int?
    private var offloadLast: Int?
    private var lastSyncAt: Date?
    private var wantsLive = false
    /// A scan was requested before Bluetooth finished powering on.
    private var wantsScan = false
    private var liveBuffer: [HistorySample] = []
    /// When the vendor realtime stream is flowing, the standard 0x2A37 heart-rate notifications carry
    /// the same beats; forwarding both would double-count R-R intervals.
    private var lastVendorRealtime: Date?
    private var identity = StrapIdentity()

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

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    // MARK: - Public API (any thread)

    /// Reconnects to the known strap, or scans for one.
    func connect() {
        queue.async { self.connectLocked() }
    }

    /// Starts a scan for a new strap even if one is remembered.
    func pairNew() {
        queue.async {
            UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
            if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
            self.peripheral = nil
            self.resetSession()
            self.startScan()
        }
    }

    func forget() {
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
        queue.async { self.startOffload(force: force) }
    }

    func setLive(_ on: Bool) {
        queue.async {
            self.wantsLive = on
            guard self.bonded, self.sessionStarted else { return }
            self.send(self.commands.toggleRealtimeHR(on))
        }
    }

    func buzz() {
        queue.async { self.send(self.commands.buzz(loops: 2)) }
    }

    /// Arms the strap's own vibrating alarm (experimental on 5.0 firmware; the app also schedules a
    /// phone notification as a backup).
    func setAlarm(_ date: Date?) {
        queue.async {
            if let date {
                self.send(self.commands.setAlarm(at: date))
            } else {
                self.send(self.commands.disableAlarm())
            }
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
        if let p = central.retrieveConnectedPeripherals(withServices: [StrapUUID.service]).first {
            attach(p)
            state = .connecting
            central.connect(p, options: nil)
            return
        }
        startScan()
    }

    private func startScan() {
        guard central.state == .poweredOn else {
            wantsScan = true
            return
        }
        wantsScan = false
        state = .scanning
        central.scanForPeripherals(withServices: [StrapUUID.service, StrapUUID.gen4Service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.state == .scanning else { return }
            self.central.stopScan()
            self.state = .noStrap
        }
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
    }

    private func resetSession() {
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
        helloTimeout?.cancel()
        offloadIdle?.cancel()
        offload = nil
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
        log("Pulsera emparejada; suscribiendo canales")
        guard let p = peripheral else { return }
        pendingSubscriptions = Set(StrapUUID.notifyChars.filter { chars[$0] != nil })
        for uuid in StrapUUID.notifyChars {
            if let c = chars[uuid] { p.setNotifyValue(true, for: c) }
        }
        if let hr = chars[StrapUUID.heartRateMeasurement] { p.setNotifyValue(true, for: hr) }
        if let b = chars[StrapUUID.batteryLevel] {
            if b.properties.contains(.notify) { p.setNotifyValue(true, for: b) }
            p.readValue(for: b)
        }
        for uuid in [StrapUUID.serialNumber, StrapUUID.firmwareRevision, StrapUUID.hardwareRevision, StrapUUID.modelNumber] {
            if let c = chars[uuid] { p.readValue(for: c) }
        }
        // Continue even if a subscription confirmation never arrives.
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.beginSession() }
    }

    private func beginSession() {
        guard bonded, !sessionStarted else { return }
        sessionStarted = true
        state = .ready
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.send(self.commands.getHello())
            let timeout = DispatchWorkItem { [weak self] in
                // No hello: set the clock anyway so the strap keeps banking data.
                self?.ensureClock(strapUnix: nil)
            }
            self.helloTimeout = timeout
            self.queue.asyncAfter(deadline: .now() + 4, execute: timeout)
        }
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
        state = .syncing(records: 0)
        log("Descargando historial…")
        send(commands.sendHistoricalData())
        armOffloadIdle()
    }

    private func armOffloadIdle() {
        offloadIdle?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.offload != nil else { return }
            self.log("La pulsera dejó de enviar; cierro la descarga")
            self.send(self.commands.abortHistorical())
            self.finishOffload()
        }
        offloadIdle = item
        queue.asyncAfter(deadline: .now() + 10, execute: item)
    }

    private func store(_ samples: [HistorySample]) -> Bool {
        guard !samples.isEmpty else { return true }
        do {
            try persist?(samples)
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
        case .chunk(let samples, let token, _):
            if store(samples) {
                send(commands.historyAck(token: token))
                state = .syncing(records: offloadRecords)
            } else {
                send(commands.abortHistorical())
                finishOffload()
            }
        case .complete(let pending):
            _ = store(pending)
            finishOffload()
        }
    }

    private func finishOffload() {
        offloadIdle?.cancel()
        offload = nil
        lastSyncAt = Date()
        if bonded { state = .ready }
        let n = offloadRecords, a = offloadFirst, b = offloadLast
        log("Descarga terminada: \(n) segundos nuevos")
        DispatchQueue.main.async { self.delegate?.strapSyncFinished(newRecords: n, firstTs: a, lastTs: b) }
    }

    // MARK: - Frame routing

    private func route(_ frame: Frame) {
        guard frame.crcOK else { return }
        let message = StrapMessage.decode(frame)
        switch message {
        case .history(let sample):
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
            state = .unsupported("Esta app es para WHOOP 5.0 / MG. Se ha encontrado una WHOOP 4.0.")
            return
        }
        central.stopScan()
        identity.name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "WHOOP"
        attach(peripheral)
        state = .connecting
        central.connect(peripheral, options: nil)
        log("Pulsera encontrada: \(identity.name)")
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
        if wasSyncing { finishOffload() }
        log("Desconectado\(error.map { ": \($0.localizedDescription)" } ?? "")")
        guard hasSavedStrap, self.peripheral?.identifier == peripheral.identifier else {
            if !hasSavedStrap { state = .noStrap }
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
                state = .unsupported("Esta app es para WHOOP 5.0 / MG. Se ha encontrado una WHOOP 4.0.")
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
                    log("La pulsera rechaza el emparejamiento (probablemente sigue vinculada a la app de WHOOP)")
                } else {
                    log("Escritura fallida: \(error.localizedDescription)")
                }
            }
            return
        }
        if !bonded { onBonded() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("Suscripción \(characteristic.uuid.uuidString) falló: \(error.localizedDescription)")
        }
        pendingSubscriptions.remove(characteristic.uuid)
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
                route(frame)
            }
        }
    }
}
