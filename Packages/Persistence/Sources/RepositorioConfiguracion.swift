import Domain
import Foundation
import PostgresNIO

public struct RepositorioConfiguracion: Sendable {
    let db: BaseDeDatos

    public init(db: BaseDeDatos) {
        self.db = db
    }

    public func valores() async throws -> ValoresConfiguracion {
        try await db.leer { conexion, logger in
            var json: [String: String] = [:]
            for fila in try await conexion.ejecutar("SELECT clave, valor::text FROM configuracion", logger) {
                let (clave, valor) = try fila.decode((String, String).self)
                json[clave] = valor
            }
            return ValoresConfiguracion(json: json)
        }
    }

    /// Guarda varios valores (JSON ya codificado) en una sola transacción.
    public func guardar(_ valores: [ClaveConfiguracion: String], por: Int64) async throws {
        try await db.transaccion(usuario: por) { conexion, logger in
            for (clave, json) in valores {
                try await conexion.ejecutar("""
                    INSERT INTO configuracion (clave, valor) VALUES (\(clave.rawValue), \(json)::jsonb)
                    ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor
                    WHERE configuracion.valor IS DISTINCT FROM EXCLUDED.valor
                    """, logger)
            }
        }
    }
}
