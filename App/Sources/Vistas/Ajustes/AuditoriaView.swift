import Domain
import Persistence
import SwiftUI

@MainActor
@Observable
final class ModeloAuditoria {
    var entradas: [EntradaAuditoria] = []
    var tablas: [String] = []
    var tabla: String?
    var seleccion: EntradaAuditoria.ID?
    var error: String?

    func cargar(_ estado: EstadoApp) async {
        guard let db = estado.db else { return }
        let repositorio = RepositorioAuditoria(db: db)
        do {
            tablas = try await repositorio.tablas()
            entradas = try await repositorio.recientes(tabla: tabla, limite: 300)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var seleccionada: EntradaAuditoria? {
        entradas.first { $0.id == seleccion }
    }
}

/// Quién cambió qué y cuándo. Solo lectura: la auditoría no se puede borrar.
struct AuditoriaView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var modelo = ModeloAuditoria()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Tabla", selection: $modelo.tabla) {
                    Text("Todas").tag(String?.none)
                    ForEach(modelo.tablas, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(maxWidth: 260)
                Spacer()
                Button("Actualizar") { Task { await modelo.cargar(estado) } }
            }
            HSplitView {
                Table(modelo.entradas, selection: $modelo.seleccion) {
                    TableColumn("Fecha") { e in Text(e.fecha.formatted(date: .abbreviated, time: .standard)) }
                    TableColumn("Usuario", value: \.usuario)
                    TableColumn("Tabla", value: \.tabla)
                    TableColumn("Registro") { e in Text(String(e.registroId)) }
                    TableColumn("Acción") { e in Text(e.accion.nombreVisible) }
                }
                .frame(minWidth: 480)
                detalle
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let error = modelo.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .task { await modelo.cargar(estado) }
        .onChange(of: modelo.tabla) { Task { await modelo.cargar(estado) } }
    }

    @ViewBuilder
    private var detalle: some View {
        if let e = modelo.seleccionada {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(e.accion.nombreVisible) en \(e.tabla) #\(e.registroId)").font(.headline)
                    Text("\(e.usuario) · \(e.fecha.formatted(date: .long, time: .standard))")
                        .foregroundStyle(.secondary)
                    Divider()
                    if e.accion == .cambio {
                        ForEach(e.camposCambiados, id: \.campo) { c in
                            VStack(alignment: .leading) {
                                Text(c.campo).font(.caption.bold())
                                Text("\(c.antes)  →  \(c.despues)").textSelection(.enabled)
                            }
                        }
                    } else {
                        Text((e.despues ?? e.antes) ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        } else {
            Text("Elige un cambio para ver el detalle.")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}
