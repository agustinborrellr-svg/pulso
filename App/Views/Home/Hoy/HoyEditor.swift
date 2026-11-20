import SwiftUI
import PulsoStore

/// «Personalizar Hoy»: the fixed top shown locked, then your blocks to remove or drag into order, and «Añadir bloque».
struct HoyEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var raw: String
    @State private var items: [HoyBlock] = []
    @State private var adding = false
    var startAdding = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Personalizar Hoy").hoyFont(17, .semibold, relativeTo: .headline).foregroundStyle(Hoy.t1)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Button { save(); dismiss() } label: {
                        Text("Hecho").hoyFont(17, .semibold, relativeTo: .headline).foregroundStyle(Hoy.t1)
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(Hoy.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            List {
                Section {
                    VStack(spacing: 0) {
                        fixedRow("Puntuaciones y monitor", thumb: .scores)
                        Rectangle().fill(Hoy.sep).frame(height: 1).padding(.leading, 72)
                        fixedRow("Ahora", thumb: .ahora)
                    }
                    .opacity(0.55)
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Hoy.card))
                    .listRowSeparator(.hidden)
                } header: {
                    Label("Fijo", systemImage: "lock.fill").hoyFont(15, .medium).foregroundStyle(Hoy.t2).textCase(nil)
                }
                Section {
                    ForEach(items) { b in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation { items.removeAll { $0 == b } }
                            } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 22))
                                    .symbolRenderingMode(.palette).foregroundStyle(.white, HoyLevel.baja.mark)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Quitar \(b.title)")
                            BlockThumb(kind: .block(b))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.title).hoyFont(17, .semibold).foregroundStyle(Hoy.t1).lineLimit(1)
                                Text(b.subtitle).hoyFont(14).foregroundStyle(Hoy.t2).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 10))
                        .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Hoy.card))
                        .listRowSeparator(.hidden)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Tus bloques").hoyFont(15, .medium).foregroundStyle(Hoy.t2).textCase(nil)
                }
                Section {
                    Button { adding = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 22))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, HoyLevel.buena.mark)
                            Text("Añadir bloque").hoyFont(17, .semibold).foregroundStyle(Hoy.t1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderless)
                    .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Hoy.fill))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .listRowSpacing(10)
            .listSectionSpacing(18)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .background(Hoy.bg.ignoresSafeArea())
        .onAppear { items = HoyLayout.decode(raw) }
        .task {
            // A sheet can't open while the editor itself is still sliding in.
            guard startAdding else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            adding = true
        }
        .sheet(isPresented: $adding) {
            HoyAddSheet(items: $items)
        }
        .preferredColorScheme(.dark)
    }

    private func save() { raw = HoyLayout.encode(items) }

    private func fixedRow(_ title: String, thumb: BlockThumb.Kind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Hoy.t3)
                .frame(width: 22, height: 22).background(Hoy.fill, in: Circle())
            BlockThumb(kind: thumb)
            Text(title).hoyFont(17, .medium).foregroundStyle(Hoy.t1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), fijo")
    }
}

/// «Añadir a Hoy»: blocks grouped by Recuperación / Sueño / Actividad / Cuerpo, only those with real data. Available
/// ones first with a green +, the ones already on Hoy after with a grey ✓.
struct HoyAddSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [HoyBlock]

    var body: some View {
        let day = model.selected ?? model.today
        VStack(spacing: 0) {
            ZStack {
                Text("Añadir a Hoy").hoyFont(17, .semibold, relativeTo: .headline).foregroundStyle(Hoy.t1)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Hoy.t2)
                            .frame(width: 32, height: 32).background(Hoy.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cerrar")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(HoyBlock.Group.allCases, id: \.self) { g in
                        let blocks = HoyBlock.allCases.filter { $0.group == g && (items.contains($0) || model.hoyHasData($0, day: day)) }
                        let sorted = blocks.filter { !items.contains($0) } + blocks.filter { items.contains($0) }
                        if !sorted.isEmpty {
                            Text(g.rawValue).hoyFont(15, .medium).foregroundStyle(Hoy.t2)
                                .padding(.leading, 4).padding(.top, 12)
                            VStack(spacing: 0) {
                                ForEach(Array(sorted.enumerated()), id: \.element) { i, b in
                                    if i > 0 { Rectangle().fill(Hoy.sep).frame(height: 1).padding(.leading, 72) }
                                    row(b)
                                }
                            }
                            .padding(.horizontal, 12)
                            .background(Hoy.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Hoy.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func row(_ b: HoyBlock) -> some View {
        let added = items.contains(b)
        return HStack(spacing: 12) {
            BlockThumb(kind: .block(b), background: Hoy.bg)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.title).hoyFont(17, .semibold).foregroundStyle(Hoy.t1).lineLimit(1)
                Text(b.subtitle).hoyFont(14).foregroundStyle(Hoy.t2).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            Button {
                withAnimation { items.append(b) }
            } label: {
                if added {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Hoy.t3)
                        .frame(width: 30, height: 30).background(Hoy.fill2.opacity(0.6), in: Circle())
                } else {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(HoyLevel.buena.mark, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(added)
            .accessibilityLabel(added ? "\(b.title), ya en Hoy" : "Añadir \(b.title)")
        }
        .padding(.vertical, 10)
    }
}

/// A block's look in miniature: its own visualisation drawn small (schematic), on a surface one step darker.
struct BlockThumb: View {
    enum Kind {
        case scores, ahora
        case block(HoyBlock)
    }

    let kind: Kind
    var background: Color = Hoy.bg

    var body: some View {
        Canvas { ctx, size in
            draw(&ctx, size)
        }
        .frame(width: 48, height: 36)
        .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
    }

    private func wave(_ size: CGSize, amp: CGFloat, freq: CGFloat, mid: CGFloat) -> Path {
        var p = Path()
        for i in 0...40 {
            let x = 6 + (size.width - 12) * CGFloat(i) / 40
            let y = mid + amp * sin(CGFloat(i) / 40 * .pi * 2 * freq)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }

    private func bars(_ ctx: inout GraphicsContext, _ size: CGSize, _ hs: [CGFloat], _ colors: [Color]) {
        let w: CGFloat = 4, gap: CGFloat = (size.width - 12 - CGFloat(hs.count) * w) / CGFloat(max(hs.count - 1, 1))
        for (i, h) in hs.enumerated() {
            let r = CGRect(x: 6 + CGFloat(i) * (w + gap), y: size.height - 7 - h, width: w, height: h)
            ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(colors[i % colors.count]))
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        switch kind {
        case .scores:
            for (i, c) in [Hoy.recarga, Hoy.sueno, Hoy.act].enumerated() {
                var p = Path()
                p.addArc(center: CGPoint(x: 12 + CGFloat(i) * 12, y: 16), radius: 5, startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
                ctx.stroke(p, with: .color(c), style: stroke)
            }
            for i in 0..<5 {
                ctx.fill(Path(roundedRect: CGRect(x: 7 + CGFloat(i) * 7.2, y: 27, width: 5, height: 2), cornerRadius: 1), with: .color(HoyLevel.buena.mark))
            }
        case .ahora:
            ctx.stroke(wave(size, amp: 3, freq: 2.5, mid: 18), with: .color(Hoy.cor), style: stroke)
        case .block(let b):
            switch b {
            case .actividades:
                for (i, c) in [Hoy.sueno, Hoy.act, Hoy.recarga].enumerated() {
                    let y = 7 + CGFloat(i) * 7
                    ctx.fill(Path(roundedRect: CGRect(x: 7, y: y, width: 9, height: 4), cornerRadius: 2), with: .color(c))
                    ctx.fill(Path(roundedRect: CGRect(x: 19, y: y + 1, width: 18, height: 2), cornerRadius: 1), with: .color(Hoy.fill2))
                }
                ctx.fill(Path(roundedRect: CGRect(x: 7, y: 28, width: 34, height: 3), cornerRadius: 1.5), with: .color(Hoy.stDeep))
            case .anoche:
                ctx.stroke(wave(size, amp: 7, freq: 3, mid: 18), with: .color(Hoy.sueno), style: stroke)
            case .estres:
                var p = Path()
                let ys: [CGFloat] = [27, 27, 26, 12, 20, 24, 22, 26, 25]
                for (i, y) in ys.enumerated() {
                    let pt = CGPoint(x: 7 + CGFloat(i) * 4.3, y: y)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                ctx.stroke(p, with: .color(HoyLevel.buena.mark), style: stroke)
            case .tendencias:
                ctx.fill(Path(CGRect(x: 6, y: 13, width: 36, height: 10)), with: .color(Hoy.cor.opacity(0.18)))
                ctx.stroke(wave(size, amp: 4, freq: 2.5, mid: 18), with: .color(Hoy.cor), style: stroke)
            case .edadPulso:
                var real = Path(); real.move(to: CGPoint(x: 7, y: 14)); real.addLine(to: CGPoint(x: 41, y: 11))
                ctx.stroke(real, with: .color(Hoy.t3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                var p = Path(); p.move(to: CGPoint(x: 7, y: 15)); p.addLine(to: CGPoint(x: 41, y: 25))
                ctx.stroke(p, with: .color(Hoy.bien), style: stroke)
            case .estaNoche:
                ctx.fill(Path(roundedRect: CGRect(x: 10, y: 17, width: 30, height: 3), cornerRadius: 1.5), with: .color(Hoy.sueno))
                ctx.fill(Path(ellipseIn: CGRect(x: 7, y: 14.5, width: 8, height: 8)), with: .color(Hoy.t1))
            case .tuSemana:
                bars(&ctx, size, [12, 18, 9, 16, 20, 14, 18], [HoyLevel.buena.mark, Hoy.recarga, HoyLevel.justa.mark, HoyLevel.buena.mark])
            case .cargaSemana:
                ctx.fill(Path(roundedRect: CGRect(x: 7, y: 17, width: 34, height: 3), cornerRadius: 1.5), with: .color(Hoy.fill2))
                ctx.fill(Path(CGRect(x: 18, y: 17, width: 12, height: 3)), with: .color(HoyLevel.buena.mark.opacity(0.6)))
                ctx.fill(Path(ellipseIn: CGRect(x: 21, y: 14.5, width: 8, height: 8)), with: .color(Hoy.act))
            case .pasos:
                bars(&ctx, size, [10, 15, 8, 18, 13, 16, 21], [Hoy.act.opacity(0.6)])
            case .racha:
                bars(&ctx, size, [9, 11, 18, 19, 17, 20, 18], [Hoy.fill2, Hoy.fill2, Hoy.sueno, Hoy.sueno])
            case .meVoyADormir:
                for i in 0..<3 {
                    let y = 10 + CGFloat(i) * 7
                    ctx.fill(Path(roundedRect: CGRect(x: 7, y: y, width: 34, height: 2), cornerRadius: 1), with: .color(Hoy.fill2))
                    ctx.fill(Path(roundedRect: CGRect(x: 14 + CGFloat(i) * 2, y: y - 1.5, width: 18, height: 5), cornerRadius: 2.5), with: .color(Hoy.sueno.opacity(0.8)))
                }
            case .constantes:
                for i in 0..<3 {
                    let y = 10 + CGFloat(i) * 8
                    ctx.fill(Path(roundedRect: CGRect(x: 7, y: y, width: 34, height: 2), cornerRadius: 1), with: .color(Hoy.fill2))
                    ctx.fill(Path(ellipseIn: CGRect(x: 15 + CGFloat(i * 6), y: y - 2.5, width: 7, height: 7)), with: .color(i == 1 ? Hoy.cor : Hoy.cons))
                }
            }
        }
    }
}
