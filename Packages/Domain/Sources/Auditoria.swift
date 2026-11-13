import Foundation

/// Una fila de la tabla `auditoria`: quién cambió qué y cuándo.
public struct EntradaAuditoria: Sendable, Hashable, Identifiable {
    public enum Accion: String, Sendable {
        case alta = "INSERT"
        case cambio = "UPDATE"
        case borrado = "DELETE"

        public var nombreVisible: String {
            switch self {
            case .alta: "Alta"
            case .cambio: "Cambio"
            case .borrado: "Borrado"
            }
        }
    }

    public let id: Int64
    public let tabla: String
    public let registroId: Int64
    public let accion: Accion
    public let usuario: String
    public let fecha: Date
    /// JSON del registro antes y después del cambio.
    public let antes: String?
    public let despues: String?

    public init(
        id: Int64, tabla: String, registroId: Int64, accion: Accion, usuario: String,
        fecha: Date, antes: String?, despues: String?
    ) {
        self.id = id
        self.tabla = tabla
        self.registroId = registroId
        self.accion = accion
        self.usuario = usuario
        self.fecha = fecha
        self.antes = antes
        self.despues = despues
    }

    /// Campos que cambian entre `antes` y `despues`, sin las columnas de control.
    public var camposCambiados: [CampoCambiado] {
        let a = Self.objeto(antes)
        let d = Self.objeto(despues)
        let ignorar: Set<String> = ["actualizado_en", "actualizado_por", "version", "creado_en", "creado_por"]
        let claves = Set(a.keys).union(d.keys).subtracting(ignorar).sorted()
        return claves.compactMap { clave in
            let va = a[clave] ?? "—"
            let vd = d[clave] ?? "—"
            return va == vd ? nil : CampoCambiado(campo: clave, antes: va, despues: vd)
        }
    }

    public struct CampoCambiado: Sendable, Hashable {
        public let campo: String
        public let antes: String
        public let despues: String
    }

    private static func objeto(_ json: String?) -> [String: String] {
        guard let json, let datos = json.data(using: .utf8),
              let objeto = try? JSONSerialization.jsonObject(with: datos) as? [String: Any]
        else { return [:] }
        var resultado: [String: String] = [:]
        for (clave, valor) in objeto {
            resultado[clave] = valor is NSNull ? "—" : "\(valor)"
        }
        return resultado
    }
}
