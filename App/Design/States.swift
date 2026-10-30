import SwiftUI

// MARK: - Connection

/// What Pulso knows about the strap, split in two: the Bluetooth link and how fresh the data is.
/// A strap can be linked and still have old data (sync pending), or stream live pulse without a full pairing.
struct ConnectionStatus: Equatable {
    enum Kind: Equatable { case connected, syncing, connecting, pending, disconnected, problem, noStrap }

    let kind: Kind
    /// Badge text: "Conectada", "Sincronizando"…
    let title: String
    /// One-line detail: "Sincronizado hace 5 min".
    private(set) var line: String
    let liveFresh: Bool

    /// Data older than this with the strap linked = "pendiente de actualizar" (auto-sync runs every 30 min).
    static let staleAfter: TimeInterval = 2 * 3600

    @MainActor init(_ model: AppModel, now: Date = Date()) {
        let live = (model.lastLiveAt.map { now.timeIntervalSince($0) < 6 } ?? false) && model.liveHR != nil
        liveFresh = live
        let synced = model.lastSync.map { "Sincronizado \(Fmt.relative($0))" } ?? "Sin descargas todavía"
        let stale = model.lastSync.map { now.timeIntervalSince($0) > Self.staleAfter } ?? true
        switch model.strapState {
        case .syncing(let n):
            kind = .syncing; title = "Sincronizando"; line = n > 0 ? "Descargando… \(n) s" : "Descargando…"
        case .ready:
            if stale {
                kind = .pending; title = "Pendiente de actualizar"; line = model.lastSync == nil ? "Conectada · sin descargas todavía" : "Conectada · \(synced.lowercased())"
            } else {
                kind = .connected; title = "Conectada"; line = synced
            }
        case .scanning, .connecting, .pairing:
            kind = .connecting; title = "Conectando"
            line = model.strapState == .pairing ? "Emparejando" : (model.strapState == .scanning ? "Buscando pulseras" : "Buscando tu pulsera")
        case .pairingRefused:
            kind = .problem; title = live ? "Solo pulso en directo" : "Emparejamiento rechazado"
            line = live ? "Sin descarga del histórico" : "Emparejamiento rechazado"
        case .bluetoothOff:
            kind = .problem; title = "Bluetooth apagado"; line = title
        case .unauthorized:
            kind = .problem; title = "Sin permiso Bluetooth"; line = title
        case .unsupported:
            kind = .problem; title = "No compatible"; line = "Pulsera no compatible"
        case .noStrap:
            if model.strap.hasSavedStrap {
                kind = .disconnected; title = "Desconectada"; line = model.lastSync == nil ? "Desconectada" : "Desconectada · \(synced.lowercased())"
            } else {
                kind = .noStrap; title = "Sin pulsera"; line = "Sin pulsera"
            }
        }
        if model.analyzing {
            line = "Analizando \(Int(model.analysisProgress * 100))%"
        }
    }

    var color: Color {
        switch kind {
        case .connected: return Theme.green
        case .syncing: return Theme.strain
        case .connecting: return Theme.link
        case .pending: return Theme.yellow
        case .disconnected, .noStrap: return Theme.secondary
        case .problem: return Theme.red
        }
    }

    var symbol: String {
        switch kind {
        case .connected: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .connecting: return "dot.radiowaves.left.and.right"
        case .pending: return "clock.badge.exclamationmark"
        case .disconnected: return "bolt.horizontal.circle"
        case .noStrap: return "plus.circle"
        case .problem: return "exclamationmark.triangle.fill"
        }
    }

    var busy: Bool { kind == .syncing || kind == .connecting }

    func accessibilityText(battery: Double?) -> String {
        var parts = [title]
        if line != title { parts.append(line) }
        if let battery { parts.append("batería \(Int(battery)) %") }
        return parts.joined(separator: ", ")
    }
}

/// "● CONECTADA" pill. While busy the dot becomes a small pulse trace.
struct ConnectionBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 7) {
            if status.busy {
                PulseLoader(phase: .running(progress: nil), style: .compact, tint: status.color)
                    .frame(width: 22, height: 12)
            } else {
                Circle().fill(status.color).frame(width: 7, height: 7)
            }
            Caps(status.title, size: 11, color: status.color, weight: .semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pulsera: \(status.title)")
    }
}

// MARK: - Empty / error / loading

/// Nothing to show yet, with an optional way forward.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        StateCard(icon: icon, tint: Theme.secondary, title: title, message: message, actionTitle: actionTitle, action: action)
    }
}

/// Something failed: says what, and offers a retry when there is one.
struct ErrorState: View {
    var title = "Algo ha fallado"
    let message: String
    var retryTitle = "Reintentar"
    var retry: (() -> Void)?

    var body: some View {
        StateCard(icon: "exclamationmark.triangle", tint: Theme.red, title: title, message: message,
                  actionTitle: retry == nil ? nil : retryTitle, action: retry)
    }
}

/// Work in progress: the pulse trace, a title and optional progress (0…1).
struct LoadingState: View {
    let title: String
    var message: String?
    var progress: Double?

    var body: some View {
        VStack(spacing: 14) {
            PulseLoader(phase: .running(progress: progress))
                .frame(width: 168, height: 56)
            Text(title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct StateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).scaledFont(32, weight: .light, relativeTo: .title1, maxScale: 1.3).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryCapsuleStyle())
                    .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
