import Domain
import Persistence
import SwiftUI

@MainActor
@Observable
final class ModeloTienda {
    var nombre = ""
    var nif = ""
    var direccion = ""
    var iban = ""
    var textoPie = ""
    var validezPresupuesto = 30
    var minutosBloqueo = 10
    var mensaje: String?
    var guardando = false

    func cargar(_ v: ValoresConfiguracion) {
        nombre = v.texto(.tiendaNombre) ?? ""
        nif = v.texto(.tiendaNIF) ?? ""
        direccion = v.texto(.tiendaDireccion) ?? ""
        iban = v.texto(.tiendaIBAN) ?? ""
        textoPie = v.texto(.reciboTextoPie) ?? ""
        validezPresupuesto = v.entero(.presupuestoValidezDias) ?? 30
        minutosBloqueo = v.politicaBloqueo.minutos
    }

    func guardar(_ estado: EstadoApp) async {
        guard let db = estado.db, let usuario = estado.usuario else { return }
        guardando = true
        defer { guardando = false }
        let limpio = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        do {
            try await RepositorioConfiguracion(db: db).guardar([
                .tiendaNombre: ValoresConfiguracion.codificar(limpio(nombre)),
                .tiendaNIF: ValoresConfiguracion.codificar(limpio(nif).uppercased()),
                .tiendaDireccion: ValoresConfiguracion.codificar(limpio(direccion)),
                .tiendaIBAN: ValoresConfiguracion.codificar(limpio(iban).uppercased()),
                .reciboTextoPie: ValoresConfiguracion.codificar(limpio(textoPie)),
                .presupuestoValidezDias: ValoresConfiguracion.codificar(max(1, validezPresupuesto)),
                .sesionBloqueoMinutos: ValoresConfiguracion.codificar(max(0, minutosBloqueo)),
            ], por: usuario.id)
            await estado.recargarConfiguracion()
            mensaje = "Guardado."
        } catch {
            mensaje = error.localizedDescription
        }
    }
}

struct TiendaView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var modelo = ModeloTienda()

    var body: some View {
        Form {
            Section("Datos de la tienda (salen en recibos y presupuestos)") {
                TextField("Nombre", text: $modelo.nombre)
                TextField("NIF", text: $modelo.nif)
                TextField("Dirección", text: $modelo.direccion, axis: .vertical)
                    .lineLimit(2...4)
                TextField("IBAN", text: $modelo.iban)
                TextField("Texto al pie del recibo", text: $modelo.textoPie, axis: .vertical)
                    .lineLimit(2...4)
                Stepper("Validez de los presupuestos: \(modelo.validezPresupuesto) días",
                        value: $modelo.validezPresupuesto, in: 1...365)
            }
            Section {
                Stepper(modelo.minutosBloqueo == 0
                        ? "Bloquear la sesión sin uso: nunca"
                        : "Bloquear la sesión tras \(modelo.minutosBloqueo) minutos sin uso",
                        value: $modelo.minutosBloqueo, in: 0...120)
            } header: {
                Text("Sesión")
            } footer: {
                Text("Al bloquearse hay que volver a escribir el PIN.")
            }
            Section {
                HStack {
                    if let mensaje = modelo.mensaje { Text(mensaje).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Guardar") { Task { await modelo.guardar(estado) } }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!estado.esTitular || modelo.guardando)
                }
            } footer: {
                if !estado.esTitular { Text("Solo el titular puede cambiar estos datos.") }
            }
        }
        .formStyle(.grouped)
        .onAppear { modelo.cargar(estado.configuracion) }
    }
}
