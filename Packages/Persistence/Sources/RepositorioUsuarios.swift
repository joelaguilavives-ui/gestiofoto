import Domain
import Foundation
import PostgresNIO

public struct RepositorioUsuarios: Sendable {
    let db: BaseDeDatos

    public init(db: BaseDeDatos) {
        self.db = db
    }

    private static let columnas =
        "id, nombre, rol, activo, bloqueado_hasta, ultimo_acceso, version"

    static func usuario(_ fila: PostgresRow) throws -> Usuario {
        let (id, nombre, rol, activo, bloqueado, acceso, version) =
            try fila.decode((Int64, String, String, Bool, Date?, Date?, Int32).self)
        return Usuario(
            id: id, nombre: nombre, rol: Rol(rawValue: rol) ?? .dependiente, activo: activo,
            bloqueadoHasta: bloqueado, ultimoAcceso: acceso, version: Int(version))
    }

    /// Usuarios que pueden iniciar sesión (o todos, para Ajustes).
    public func todos(incluirInactivos: Bool = false) async throws -> [Usuario] {
        let filtro = incluirInactivos ? "" : "AND activo"
        return try await db.leer { conexion, logger in
            try await conexion.ejecutar("""
                SELECT \(unescaped: Self.columnas) FROM usuario
                 WHERE NOT es_sistema \(unescaped: filtro)
                 ORDER BY nombre
                """, logger).map(Self.usuario)
        }
    }

    public func usuario(id: Int64) async throws -> Usuario {
        try await db.leer { conexion, logger in
            let consulta: PostgresQuery = "SELECT \(unescaped: Self.columnas) FROM usuario WHERE id = \(id)"
            guard let fila = try await conexion.ejecutar(consulta, logger).first else {
                throw ErrorBaseDeDatos.noEncontrado
            }
            return try Self.usuario(fila)
        }
    }

    /// `true` si ya hay algún usuario activo (si no, hay que crear el primer titular).
    public func hayUsuarios() async throws -> Bool {
        try await db.leer { conexion, logger in
            try await conexion
                .ejecutar("SELECT count(*) FROM usuario WHERE NOT es_sistema AND activo", logger)
                .first!.decode(Int64.self) > 0
        }
    }

    /// Inicio de sesión. Cuenta los fallos y bloquea tras 5 seguidos.
    public func verificarPIN(usuario: Int64, pin: String) async throws -> Bool {
        try await db.transaccion(usuario: nil) { conexion, logger in
            try await conexion
                .ejecutar("SELECT verificar_pin(\(usuario), \(pin))", logger)
                .first!.decode(Bool.self)
        }
    }

    /// Alta de usuario (solo titular). `por` = quien lo crea; para el primer
    /// titular, el usuario Sistema (1) con la conexión del propietario.
    public func crear(nombre: String, rol: Rol, pin: String, por: Int64) async throws -> Int64 {
        try await db.transaccion(usuario: por) { conexion, logger in
            try await conexion
                .ejecutar("SELECT crear_usuario(\(nombre), \(rol.rawValue), \(pin))", logger)
                .first!.decode(Int64.self)
        }
    }

    public func establecerPIN(usuario: Int64, pin: String, por: Int64) async throws {
        try await db.transaccion(usuario: por) { conexion, logger in
            _ = try await conexion.ejecutar("SELECT establecer_pin(\(usuario), \(pin))", logger)
        }
    }

    /// Guarda nombre, rol y estado. Falla con `.conflictoVersion` si otra persona
    /// lo cambió desde que se leyó.
    public func guardar(_ u: Usuario, por: Int64) async throws -> Usuario {
        try await db.transaccion(usuario: por) { conexion, logger in
            let filas = try await conexion.ejecutar("""
                UPDATE usuario
                   SET nombre = \(u.nombre), rol = \(u.rol.rawValue), activo = \(u.activo)
                 WHERE id = \(u.id) AND version = \(Int32(u.version))
                RETURNING id, nombre, rol, activo, bloqueado_hasta, ultimo_acceso, version
                """, logger)
            guard let fila = filas.first else { throw ErrorBaseDeDatos.conflictoVersion }
            return try Self.usuario(fila)
        }
    }
}
