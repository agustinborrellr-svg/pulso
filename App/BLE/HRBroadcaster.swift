import Foundation
import CoreBluetooth
import PulsoIntegrations

/// Makes the iPhone advertise the standard Bluetooth Heart Rate service (0x180D) and forwards the
/// strap's live pulse to it, so Zwift, Peloton, gym machines, bike computers and other apps can
/// use the WHOOP as an ordinary heart-rate sensor.
final class HRBroadcaster: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager?
    private var measurement: CBMutableCharacteristic?
    private var subscribers = 0
    private(set) var isOn = false
    var onState: ((String) -> Void)?

    func start() {
        isOn = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: nil)
        } else if manager?.state == .poweredOn {
            publish()
        }
    }

    func stop() {
        isOn = false
        manager?.stopAdvertising()
        manager?.removeAllServices()
        measurement = nil
        subscribers = 0
        onState?("Apagado")
    }

    /// Call on every live heart-rate reading.
    func send(heartRate: Int, rr: [Int]) {
        guard isOn, subscribers > 0, let m = measurement, let mgr = manager else { return }
        let value = Data(HeartRateBroadcast.measurement(heartRate: heartRate, rrMilliseconds: rr))
        _ = mgr.updateValue(value, for: m, onSubscribedCentrals: nil)
    }

    private func publish() {
        guard let mgr = manager, measurement == nil else { return }
        let hr = CBMutableCharacteristic(type: CBUUID(string: HeartRateBroadcast.measurementUUID),
                                         properties: [.notify], value: nil, permissions: [.readable])
        let location = CBMutableCharacteristic(type: CBUUID(string: HeartRateBroadcast.bodyLocationUUID),
                                               properties: [.read], value: Data([HeartRateBroadcast.bodyLocationWrist]),
                                               permissions: [.readable])
        let service = CBMutableService(type: CBUUID(string: HeartRateBroadcast.serviceUUID), primary: true)
        service.characteristics = [hr, location]
        mgr.add(service)
        measurement = hr
        mgr.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: HeartRateBroadcast.serviceUUID)],
            CBAdvertisementDataLocalNameKey: "Pulso HR",
        ])
        onState?("Emitiendo como «Pulso HR»")
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if isOn { publish() }
        case .unauthorized:
            onState?("Sin permiso de Bluetooth")
        default:
            measurement = nil
            onState?("Bluetooth no disponible")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribers += 1
        onState?("Conectado a \(subscribers) dispositivo\(subscribers == 1 ? "" : "s")")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers = max(0, subscribers - 1)
        onState?(subscribers == 0 ? "Emitiendo como «Pulso HR»" : "Conectado a \(subscribers) dispositivo\(subscribers == 1 ? "" : "s")")
    }
}
