import Domain
import Foundation
import PostgresNIO

public struct RepositorioAuditoria: Sendable {
    let db: BaseDeDatos

    public init(db: BaseDeDatos) {
        self.db = db
    }

    static func entrada(_ fila: PostgresRow) throws -> EntradaAuditoria {
        let (id, tabla, registro, accion, usuario, fecha, antes, despues) =
            try fila.decode((Int64, String, Int64, String, String, Date, String?, String?).self)
        return EntradaAuditoria(
            id: id, tabla: tabla, registroId: registro,
            accion: EntradaAuditoria.Accion(rawValue: accion) ?? .cambio,
            usuario: usuario, fecha: fecha, antes: antes, despues: despues)
    }

    /// Últimos cambios, opcionalmente de una sola tabla.
    public func recientes(tabla: String? = nil, limite: Int = 200) async throws -> [EntradaAuditoria] {
        try await db.leer { conexion, logger in
            try await conexion.ejecutar("""
                SELECT a.id, a.tabla, a.registro_id, a.accion, u.nombre, a.fecha,
                       a.antes::text, a.despues::text
                  FROM auditoria a JOIN usuario u ON u.id = a.usuario_id
                 WHERE (\(tabla)::text IS NULL OR a.tabla = \(tabla))
                 ORDER BY a.id DESC
                 LIMIT \(limite)
                """, logger).map(Self.entrada)
        }
    }

    /// «Historial» de un registro concreto (ficha de cliente, pedido…).
    public func historial(tabla: String, registro: Int64) async throws -> [EntradaAuditoria] {
        try await db.leer { conexion, logger in
            try await conexion.ejecutar("""
                SELECT a.id, a.tabla, a.registro_id, a.accion, u.nombre, a.fecha,
                       a.antes::text, a.despues::text
                  FROM auditoria a JOIN usuario u ON u.id = a.usuario_id
                 WHERE a.tabla = \(tabla) AND a.registro_id = \(registro)
                 ORDER BY a.id DESC
                """, logger).map(Self.entrada)
        }
    }

    /// Tablas que tienen cambios registrados (para el filtro).
    public func tablas() async throws -> [String] {
        try await db.leer { conexion, logger in
            try await conexion
                .ejecutar("SELECT DISTINCT tabla FROM auditoria ORDER BY tabla", logger)
                .map { try $0.decode(String.self) }
        }
    }
}
