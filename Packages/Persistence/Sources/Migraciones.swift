import Foundation
import Logging
import PostgresNIO

/// Un fichero `Database/migrations/NNNN_nombre.sql`.
public struct Migracion: Sendable, Equatable {
    public let version: Int
    public let nombre: String
    public let sql: String

    public init(version: Int, nombre: String, sql: String) {
        self.version = version
        self.nombre = nombre
        // El checksum no debe depender de los saltos de línea de Windows.
        self.sql = sql.replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// Carga las migraciones de una carpeta. Exige numeración 1, 2, 3… sin huecos.
    public static func cargar(desde carpeta: URL) throws -> [Migracion] {
        let ficheros = try FileManager.default.contentsOfDirectory(atPath: carpeta.path)
            .filter { $0.hasSuffix(".sql") }
            .sorted()
        var resultado: [Migracion] = []
        for fichero in ficheros {
            let partes = fichero.split(separator: "_", maxSplits: 1)
            guard partes.count == 2, partes[0].count == 4, let version = Int(partes[0]) else {
                throw ErrorBaseDeDatos.migracionesInvalidas("nombre no válido: \(fichero)")
            }
            let sql = try String(contentsOf: carpeta.appendingPathComponent(fichero), encoding: .utf8)
            resultado.append(Migracion(version: version, nombre: fichero, sql: sql))
        }
        for (indice, migracion) in resultado.enumerated() where migracion.version != indice + 1 {
            throw ErrorBaseDeDatos.migracionesInvalidas(
                "se esperaba la versión \(indice + 1) y se encontró \(migracion.nombre)")
        }
        return resultado
    }
}

/// Aplica las migraciones pendientes al arrancar la app en el Mac principal.
/// Cada migración va en su propia transacción; nunca se aplica dos veces y, si
/// una ya aplicada ha cambiado, se detiene (CLAUDE.md: no se editan).
/// Debe usarse con la conexión del rol propietario.
public struct EjecutorMigraciones: Sendable {
    let db: BaseDeDatos
    /// Evita que dos procesos migren a la vez.
    static let claveBloqueo: Int64 = 7_212_026

    public init(db: BaseDeDatos) {
        self.db = db
    }

    /// Devuelve las versiones aplicadas en esta llamada. El seed se ejecuta
    /// siempre al final (es repetible).
    @discardableResult
    public func aplicar(_ migraciones: [Migracion], seed: String? = nil) async throws -> [Int] {
        try await db.leer { conexion, logger in
            try await Self.enTransaccion(conexion, logger) {
                try await conexion.ejecutar("SELECT pg_advisory_xact_lock(\(Self.claveBloqueo))", logger)
                try await conexion.ejecutar("""
                    CREATE TABLE IF NOT EXISTS schema_migracion (
                      version     integer     PRIMARY KEY,
                      nombre      text        NOT NULL,
                      checksum    text        NOT NULL,
                      aplicada_en timestamptz NOT NULL DEFAULT now()
                    )
                    """, logger)
            }

            var aplicadas: [Int] = []
            for migracion in migraciones.sorted(by: { $0.version < $1.version }) {
                try await Self.enTransaccion(conexion, logger) {
                    try await conexion.ejecutar("SELECT pg_advisory_xact_lock(\(Self.claveBloqueo))", logger)
                    let suma = try await conexion
                        .ejecutar("SELECT encode(sha256(convert_to(\(migracion.sql), 'UTF8')), 'hex')", logger)
                        .first!.decode(String.self)
                    let existente = try await conexion
                        .ejecutar("SELECT checksum FROM schema_migracion WHERE version = \(migracion.version)", logger)
                        .first.map { try $0.decode(String.self) }

                    if let existente {
                        guard existente == suma else {
                            throw ErrorBaseDeDatos.migracionModificada(version: migracion.version)
                        }
                        return
                    }
                    for sentencia in ScriptSQL.sentencias(migracion.sql) {
                        try await conexion.ejecutar(PostgresQuery(unsafeSQL: sentencia), logger)
                    }
                    try await conexion.ejecutar("""
                        INSERT INTO schema_migracion (version, nombre, checksum)
                        VALUES (\(migracion.version), \(migracion.nombre), \(suma))
                        """, logger)
                    aplicadas.append(migracion.version)
                }
            }

            if let seed {
                try await Self.enTransaccion(conexion, logger) {
                    for sentencia in ScriptSQL.sentencias(seed) {
                        try await conexion.ejecutar(PostgresQuery(unsafeSQL: sentencia), logger)
                    }
                }
            }
            return aplicadas
        }
    }

    /// Versiones ya aplicadas en la base de datos.
    public func aplicadas() async throws -> [Int] {
        try await db.leer { conexion, logger in
            let existe = try await conexion
                .ejecutar("SELECT to_regclass('public.schema_migracion') IS NOT NULL", logger)
                .first!.decode(Bool.self)
            guard existe else { return [] }
            return try await conexion
                .ejecutar("SELECT version FROM schema_migracion ORDER BY version", logger)
                .map { fila in try Int(fila.decode(Int32.self)) }
        }
    }

    private static func enTransaccion(
        _ conexion: PostgresConnection, _ logger: Logger, _ cuerpo: () async throws -> Void
    ) async throws {
        try await conexion.ejecutar("BEGIN", logger)
        do {
            try await cuerpo()
            try await conexion.ejecutar("COMMIT", logger)
        } catch {
            _ = try? await conexion.ejecutar("ROLLBACK", logger)
            throw error
        }
    }
}
