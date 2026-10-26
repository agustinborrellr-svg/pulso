import SwiftUI
import UniformTypeIdentifiers
import PulsoAnalytics

/// Import of a WHOOP data export: add any of its CSV files (all optional, several at once), see what
/// each one is, then import.
struct WhoopImportView: View {
    @EnvironmentObject var model: AppModel
    @State private var files: [WhoopExport.File] = []
    @State private var unreadable: [String] = []
    @State private var picking = false
    @State private var working = false
    @State private var result: WhoopImportSummary?

    private var recognised: [(kind: WhoopExport.Kind, file: WhoopExport.File)] {
        files.compactMap { f in WhoopExport.kind(of: f.text).map { ($0, f) } }
    }

    private var unrecognised: [WhoopExport.File] {
        files.filter { WhoopExport.kind(of: $0.text) == nil }
    }

    var body: some View {
        List {
            Section {
                Text("En la app de WHOOP: *Más → Ajustes de la app → Exportar datos*. Te llega un .zip por correo: ábrelo en Archivos (se descomprime solo) y elige aquí los CSV que quieras.")
                    .font(.subheadline)
            }

            Section {
                ForEach(WhoopExport.Kind.allCases, id: \.self) { kind in
                    slot(kind)
                }
                ForEach(unrecognised, id: \.name) { f in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name)
                                Text("No es un archivo de WHOOP: no se importará").font(.caption).foregroundStyle(Theme.yellow)
                            }
                        } icon: {
                            Image(systemName: "questionmark.circle").foregroundStyle(Theme.yellow)
                        }
                        Spacer()
                        removeButton(f.name)
                    }
                }
                ForEach(unreadable, id: \.self) { name in
                    Label("\(name): no se ha podido leer", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.red)
                }
                Button {
                    picking = true
                } label: {
                    Label(files.isEmpty ? "Elegir archivos" : "Añadir más archivos", systemImage: "plus.circle")
                }
            } header: {
                Text("Archivos")
            } footer: {
                Text("Todos son opcionales: sube solo los que quieras. Puedes elegir varios a la vez; la app reconoce cada uno por su contenido, en español o en inglés.")
            }

            Section {
                Button {
                    working = true
                    let chosen = recognised.map(\.file)
                    // Let the spinner draw before the import runs on the main actor.
                    DispatchQueue.main.async {
                        result = model.importWhoop(chosen)
                        files = []
                        unreadable = []
                        working = false
                    }
                } label: {
                    HStack {
                        Label(importTitle, systemImage: "square.and.arrow.down")
                        if working {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(recognised.isEmpty || working)
                .opacity(recognised.isEmpty ? 0.4 : 1)
            } footer: {
                Text("Puedes repetir la importación sin miedo: no duplica entrenos ni pisa lo que hayas apuntado en el diario de Pulso. Los días que mida la pulsera mandan sobre los importados.")
            }

            if let r = result {
                resultSection(r)
            }
        }
        .navigationTitle("Importar de WHOOP")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                      allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { add(urls) }
        }
    }

    private var importTitle: String {
        let n = recognised.count
        return n == 0 ? "Importar" : "Importar \(n) archivo\(n == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func slot(_ kind: WhoopExport.Kind) -> some View {
        if let f = recognised.first(where: { $0.kind == kind })?.file {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.label)
                        Text("\(f.name) · \(rowCount(f)) filas").font(.caption).foregroundStyle(Theme.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                }
                Spacer()
                removeButton(f.name)
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label).foregroundStyle(Theme.secondary)
                    Text("Opcional · \(kind.fileName)").font(.caption).foregroundStyle(Theme.tertiary)
                }
            } icon: {
                Image(systemName: "circle.dashed").foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func removeButton(_ name: String) -> some View {
        Button {
            files.removeAll { $0.name == name }
        } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quitar \(name)")
    }

    private func rowCount(_ f: WhoopExport.File) -> Int {
        max(0, f.text.split(whereSeparator: \.isNewline).count - 1)
    }

    private func add(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
                if !unreadable.contains(name) { unreadable.append(name) }
                continue
            }
            unreadable.removeAll { $0 == name }
            let file = WhoopExport.File(name: name, text: text)
            // One file per kind: a newer pick of the same kind (or the same name) replaces the old one.
            let kind = WhoopExport.kind(of: text)
            files.removeAll { $0.name == name || (kind != nil && WhoopExport.kind(of: $0.text) == kind) }
            files.append(file)
        }
        result = nil
    }

    private func resultSection(_ r: WhoopImportSummary) -> some View {
        Section {
            if let e = r.error {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.red)
            }
            ForEach(r.files, id: \.name) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.kind?.label ?? f.name)
                    Text(fileLine(f)).font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            if r.stored.days > 0 { Label("\(r.stored.days) días en tu historial", systemImage: "calendar") }
            if r.stored.workoutsNew + r.stored.workoutsLinked + r.stored.workoutsKnown > 0 {
                Label(workoutLine(r.stored), systemImage: "figure.mixed.cardio")
            }
            if r.stored.journal > 0 { Label("\(r.stored.journal) respuestas del diario", systemImage: "book.closed") }
            if r.nothingDone && r.error == nil {
                Text("No había nada nuevo que importar.").foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Resultado")
        }
    }

    private func fileLine(_ f: WhoopExport.FileReport) -> String {
        guard f.kind != nil else { return "\(f.name): no es de WHOOP, ignorado" }
        var s = "\(f.name): \(f.used) de \(f.rows) filas"
        if f.skipped > 0 { s += " (\(f.skipped) vacías o sin datos)" }
        return s
    }

    private func workoutLine(_ r: WhoopExport.Stored) -> String {
        var parts = ["\(r.workoutsNew) entrenos nuevos"]
        if r.workoutsLinked > 0 { parts.append("\(r.workoutsLinked) unidos a los que ya tenías") }
        if r.workoutsKnown > 0 { parts.append("\(r.workoutsKnown) ya importados") }
        return parts.joined(separator: ", ")
    }
}
