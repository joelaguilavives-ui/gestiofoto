import AppKit
import Domain
import Integrations
import Persistence
import SwiftUI

@MainActor
@Observable
final class ModeloCopias {
    let servicio = ServicioCopias()
    var configuracion: ConfiguracionCopias?
    var copias: [CopiaDisponible] = []
    var ocupado: String?
    var resultado: String?
    var error: String?

    var instalado: Bool { servicio.instalado }

    func cargar() {
        guard servicio.instalado else { return }
        do {
            configuracion = try servicio.configuracion()
            copias = (try? servicio.copias()) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func guardar(_ c: ConfiguracionCopias, _ estado: EstadoApp) async {
        await tarea("Guardando…", estado) {
            try await self.servicio.guardar(c)
            if let db = estado.db, let u = estado.usuario {
                try await RepositorioConfiguracion(db: db).guardar([
                    .copiasCarpeta: ValoresConfiguracion.codificar(c.carpeta),
                    .copiasHora: ValoresConfiguracion.codificar(c.horaTexto),
                    .copiasConservarDiarias: ValoresConfiguracion.codificar(c.conservarDiarias),
                    .copiasConservarMensuales: ValoresConfiguracion.codificar(c.conservarMensuales),
                ], por: u.id)
            }
            return "Configuración guardada. Copia nocturna a las \(c.horaTexto)."
        }
    }

    func hacerCopia(_ estado: EstadoApp) async {
        await tarea("Haciendo copia…", estado) { try await self.servicio.hacerCopia() }
    }

    func restaurar(_ copia: CopiaDisponible, enPruebas: Bool, _ estado: EstadoApp) async {
        await tarea(enPruebas ? "Restaurando en la base de pruebas…" : "Restaurando la copia…", estado) {
            try await self.servicio.restaurar(copia.url, enPruebas: enPruebas)
        }
        if !enPruebas && error == nil {
            // Las conexiones se cortaron al restaurar: volver a entrar.
            estado.cerrarSesion()
        }
    }

    private func tarea(
        _ texto: String, _ estado: EstadoApp, _ trabajo: @escaping () async throws -> String
    ) async {
        ocupado = texto
        error = nil
        resultado = nil
        do {
            resultado = try await trabajo()
        } catch {
            self.error = error.localizedDescription
        }
        ocupado = nil
        cargar()
        await estado.recargarConfiguracion()
    }
}

struct CopiasView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var modelo = ModeloCopias()
    @State private var carpeta = ""
    @State private var hora = Date()
    @State private var diarias = 30
    @State private var mensuales = 12
    @State private var aRestaurar: CopiaDisponible?
    @State private var confirmacion = ""

    var body: some View {
        Form {
            Section("Estado") {
                LabeledContent("Última copia correcta") {
                    Text(estado.configuracion.fecha(.copiasUltima)?
                        .formatted(date: .long, time: .shortened) ?? "Ninguna")
                }
                if let error = estado.configuracion.texto(.copiasUltimoError) {
                    LabeledContent("Último error") { Text(error).foregroundStyle(.red) }
                }
            }

            if !estado.esMacPrincipal {
                Section {
                    Text("Las copias se hacen y se restauran en el Mac principal.")
                        .foregroundStyle(.secondary)
                }
            } else if !modelo.instalado {
                Section {
                    Text("Faltan los scripts de copias en este Mac. Ejecuta Tools/setup_server/setup.sh en el Terminal.")
                        .foregroundStyle(.orange)
                }
            } else {
                configuracionSection
                accionesSection
                listaSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            modelo.cargar()
            if let c = modelo.configuracion {
                carpeta = c.carpeta
                diarias = c.conservarDiarias
                mensuales = c.conservarMensuales
                hora = Calendar.current.date(bySettingHour: c.hora, minute: c.minuto, second: 0, of: .now) ?? .now
            }
        }
        .sheet(item: $aRestaurar) { copia in
            confirmarRestauracion(copia)
        }
    }

    private var configuracionSection: some View {
        Section("Copia nocturna") {
            HStack {
                LabeledContent("Carpeta", value: carpeta.isEmpty ? "Sin elegir" : carpeta)
                Button("Elegir…", action: elegirCarpeta)
            }
            DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
            Stepper("Conservar \(diarias) copias diarias", value: $diarias, in: 1...365)
            Stepper("Conservar \(mensuales) copias mensuales", value: $mensuales, in: 0...120)
            HStack {
                Spacer()
                Button("Guardar") {
                    let partes = Calendar.current.dateComponents([.hour, .minute], from: hora)
                    var c = modelo.configuracion ?? ConfiguracionCopias(carpeta: carpeta)
                    c.carpeta = carpeta
                    c.hora = partes.hour ?? 2
                    c.minuto = partes.minute ?? 0
                    c.conservarDiarias = diarias
                    c.conservarMensuales = mensuales
                    Task { await modelo.guardar(c, estado) }
                }
                .disabled(!estado.esTitular || modelo.ocupado != nil)
            }
        }
    }

    private var accionesSection: some View {
        Section {
            HStack {
                if let ocupado = modelo.ocupado {
                    ProgressView().controlSize(.small)
                    Text(ocupado)
                }
                Spacer()
                Button("Hacer copia ahora") { Task { await modelo.hacerCopia(estado) } }
                    .disabled(modelo.ocupado != nil)
            }
            if let resultado = modelo.resultado {
                Text(resultado)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let error = modelo.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var listaSection: some View {
        Section("Copias guardadas") {
            if modelo.copias.isEmpty {
                Text("Todavía no hay copias en la carpeta.").foregroundStyle(.secondary)
            }
            ForEach(modelo.copias) { copia in
                HStack {
                    VStack(alignment: .leading) {
                        Text(copia.fecha.formatted(date: .abbreviated, time: .shortened))
                        Text("\(nombreTipo(copia.tipo)) · \(ByteCountFormatter.string(fromByteCount: copia.bytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Comprobar en base de pruebas") {
                        Task { await modelo.restaurar(copia, enPruebas: true, estado) }
                    }
                    .disabled(modelo.ocupado != nil)
                    Button("Restaurar…") {
                        confirmacion = ""
                        aRestaurar = copia
                    }
                    .disabled(!estado.esTitular || modelo.ocupado != nil)
                }
            }
        }
    }

    /// Segunda confirmación: hay que escribir RESTAURAR (PDF §7: doble confirmación).
    private func confirmarRestauracion(_ copia: CopiaDisponible) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Restaurar la copia del \(copia.fecha.formatted(date: .long, time: .shortened))?")
                .font(.headline)
            Text("Todo lo que se haya hecho después de esa copia, en los dos Macs, se perderá. Antes de restaurar se guarda una copia del estado actual en la carpeta «previas». Las dos apps se desconectarán un momento y habrá que volver a entrar.")
                .fixedSize(horizontal: false, vertical: true)
            TextField("Escribe RESTAURAR para confirmar", text: $confirmacion)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { aRestaurar = nil }
                Button("Restaurar", role: .destructive) {
                    aRestaurar = nil
                    Task { await modelo.restaurar(copia, enPruebas: false, estado) }
                }
                .disabled(confirmacion != "RESTAURAR")
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func nombreTipo(_ t: CopiaDisponible.Tipo) -> String {
        switch t {
        case .diaria: "Diaria"
        case .mensual: "Mensual"
        case .previaRestauracion: "Antes de restaurar"
        }
    }

    private func elegirCarpeta() {
        let panel = NSOpenPanel()
        panel.title = "Carpeta para las copias de seguridad"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            carpeta = url.path
        }
    }
}
