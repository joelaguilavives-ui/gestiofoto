import Domain
import SwiftUI

/// Las 11 secciones de la barra lateral (PDF §5). En la fase 1 solo funciona
/// Ajustes; las demás muestran en qué fase llegan.
enum Seccion: String, CaseIterable, Identifiable, Hashable {
    case hoy, clientes, nuevoPedido, pedidos, laboratorio, caja, banco, gastos, campanas, informes, ajustes

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .hoy: "Hoy"
        case .clientes: "Clientes"
        case .nuevoPedido: "Nuevo pedido"
        case .pedidos: "Pedidos"
        case .laboratorio: "Laboratorio"
        case .caja: "Caja"
        case .banco: "Banco"
        case .gastos: "Gastos"
        case .campanas: "Campañas"
        case .informes: "Informes"
        case .ajustes: "Ajustes"
        }
    }

    var icono: String {
        switch self {
        case .hoy: "sun.max"
        case .clientes: "person.2"
        case .nuevoPedido: "plus.square"
        case .pedidos: "doc.text.magnifyingglass"
        case .laboratorio: "photo.stack"
        case .caja: "eurosign.circle"
        case .banco: "building.columns"
        case .gastos: "cart"
        case .campanas: "calendar"
        case .informes: "chart.bar"
        case .ajustes: "gearshape"
        }
    }

    /// Fase del plan (PDF §9) en la que llega cada sección.
    var fase: Int {
        switch self {
        case .ajustes: 1
        case .clientes, .nuevoPedido, .pedidos: 2
        case .caja, .informes: 3
        case .hoy, .laboratorio: 4
        case .campanas: 5
        case .banco, .gastos: 6
        }
    }
}

struct PrincipalView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var seccion: Seccion? = .ajustes

    var body: some View {
        NavigationSplitView {
            List(Seccion.allCases, selection: $seccion) { s in
                Label(s.titulo, systemImage: s.icono)
                    .foregroundStyle(s.fase == 1 ? .primary : .secondary)
                    .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                AvisoCopiaView()
                contenido
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let u = estado.usuario {
                    Menu {
                        Button("Bloquear  ⌃⌘L") { estado.bloquear() }
                        Button("Cerrar sesión") { estado.cerrarSesion() }
                    } label: {
                        Label(u.nombre, systemImage: "person.crop.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contenido: some View {
        switch seccion ?? .ajustes {
        case .ajustes:
            AjustesView()
        case let s:
            ContentUnavailableView {
                Label(s.titulo, systemImage: s.icono)
            } description: {
                Text("Esta sección llega en la fase \(s.fase) del plan.")
            }
        }
    }
}

/// Aviso si la última copia de seguridad tiene más de 2 días (PDF §7).
struct AvisoCopiaView: View {
    @Environment(EstadoApp.self) private var estado

    var body: some View {
        let estadoCopia = estado.configuracion.estadoCopia(ahora: .now)
        if estadoCopia.requiereAviso {
            HStack {
                Image(systemName: "externaldrive.badge.exclamationmark")
                Text(texto(estadoCopia))
                Spacer()
            }
            .padding(10)
            .background(.orange.opacity(0.18))
            .foregroundStyle(.primary)
        }
    }

    private func texto(_ e: EstadoCopia) -> String {
        let error = estado.configuracion.texto(.copiasUltimoError).map { " Último error: \($0)" } ?? ""
        switch e {
        case .nunca:
            return "Todavía no se ha hecho ninguna copia de seguridad.\(error)"
        case .antigua(let fecha), .reciente(let fecha):
            return "La última copia de seguridad es del \(fecha.formatted(date: .long, time: .shortened)).\(error)"
        }
    }
}
