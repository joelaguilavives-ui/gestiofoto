import Domain
import Foundation
import PostgresNIO
import Testing
@testable import Persistence

/// Pruebas contra un PostgreSQL 16 de pruebas (en CI, el servicio del job de
/// Linux). Se saltan si no está definida GESTIOFOTO_TEST_DB_HOST.
///
/// Variables: GESTIOFOTO_TEST_DB_HOST, _PORT (5432), _NAME (gestiofoto_test),
/// _OWNER / _OWNER_PASSWORD (propietario, superusuario en CI),
/// _APP_PASSWORD (contraseña que se dará al rol gestiofoto_app).
enum EntornoPruebas {
    static let entorno = ProcessInfo.processInfo.environment
    static let disponible = entorno["GESTIOFOTO_TEST_DB_HOST"] != nil

    static var configuracion: ConfiguracionConexion {
        ConfiguracionConexion(
            servidor: entorno["GESTIOFOTO_TEST_DB_HOST"] ?? "localhost",
            puerto: Int(entorno["GESTIOFOTO_TEST_DB_PORT"] ?? "") ?? 5432,
            baseDeDatos: entorno["GESTIOFOTO_TEST_DB_NAME"] ?? "gestiofoto_test",
            esMacPrincipal: true,
            modoTLS: .desactivado)
    }

    static let contrasenaApp = entorno["GESTIOFOTO_TEST_DB_APP_PASSWORD"] ?? "app"

    static func propietario() throws -> BaseDeDatos {
        try BaseDeDatos(
            configuracion: configuracion,
            usuario: entorno["GESTIOFOTO_TEST_DB_OWNER"] ?? "postgres",
            contrasena: entorno["GESTIOFOTO_TEST_DB_OWNER_PASSWORD"] ?? "postgres")
    }

    static func app() throws -> BaseDeDatos {
        try BaseDeDatos(configuracion: configuracion, usuario: "gestiofoto_app", contrasena: contrasenaApp)
    }

    static func migraciones() throws -> [Migracion] {
        try Migracion.cargar(desde: Rutas.repositorio.appendingPathComponent("Database/migrations"))
    }

    static func seed() throws -> String {
        try String(contentsOf: Rutas.repositorio.appendingPathComponent("Database/seed/seed.sql"), encoding: .utf8)
    }
}

/// Ejecuta `cuerpo` con la base de datos lanzada; la cierra al terminar.
func conBase<T: Sendable>(
    _ db: BaseDeDatos, _ cuerpo: @Sendable (BaseDeDatos) async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: Void.self) { grupo in
        grupo.addTask { await db.ejecutar() }
        defer { grupo.cancelAll() }
        return try await cuerpo(db)
    }
}

/// Prepara la base: rol de la app, migraciones y seed. Repetible.
func prepararBase() async throws {
    try await conBase(try EntornoPruebas.propietario()) { db in
        try await db.leer { conexion, logger in
            _ = try await conexion.ejecutar(PostgresQuery(unsafeSQL: """
                DO $$ BEGIN
                  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gestiofoto_app') THEN
                    CREATE ROLE gestiofoto_app LOGIN PASSWORD '\(EntornoPruebas.contrasenaApp)';
                  END IF;
                END $$
                """), logger)
        }
        try await EjecutorMigraciones(db: db).aplicar(try EntornoPruebas.migraciones(), seed: try EntornoPruebas.seed())
    }
}

@Suite("PostgreSQL (integración)", .serialized, .enabled(if: EntornoPruebas.disponible))
struct BaseDeDatosIntegracionTests {
    init() async throws {
        try await prepararBase()
    }

    @Test func migracionesRepetiblesYDetectaCambios() async throws {
        try await conBase(try EntornoPruebas.propietario()) { db in
            let ejecutor = EjecutorMigraciones(db: db)
            let migraciones = try EntornoPruebas.migraciones()
            #expect(try await ejecutor.aplicar(migraciones).isEmpty)
            #expect(try await ejecutor.aplicadas() == migraciones.map(\.version))

            var alterada = migraciones
            alterada[0] = Migracion(version: 1, nombre: alterada[0].nombre, sql: alterada[0].sql + "\n-- cambio")
            await #expect(throws: ErrorBaseDeDatos.migracionModificada(version: 1)) {
                try await ejecutor.aplicar(alterada)
            }
        }
    }

    @Test func usuariosPINyConflictoDeVersion() async throws {
        let nombre = "Prueba \(UUID().uuidString.prefix(6))"
        let id = try await conBase(try EntornoPruebas.propietario()) { db in
            try await RepositorioUsuarios(db: db).crear(nombre: nombre, rol: .titular, pin: "1234", por: 1)
        }
        try await conBase(try EntornoPruebas.app()) { db in
            let repo = RepositorioUsuarios(db: db)
            #expect(try await repo.hayUsuarios())
            #expect(try await repo.todos().contains { $0.id == id })
            #expect(try await repo.verificarPIN(usuario: id, pin: "1234"))
            #expect(try await repo.verificarPIN(usuario: id, pin: "0000") == false)

            let leido = try await repo.usuario(id: id)
            var cambio = leido
            cambio.nombre = nombre + " B"
            let guardado = try await repo.guardar(cambio, por: id)
            #expect(guardado.version == leido.version + 1)

            // La segunda persona guarda con la versión antigua: conflicto.
            var otro = leido
            otro.nombre = nombre + " C"
            await #expect(throws: ErrorBaseDeDatos.conflictoVersion) {
                try await repo.guardar(otro, por: id)
            }

            // Sin firma no se guarda nada.
            await #expect(throws: (any Error).self) {
                try await db.transaccion(usuario: nil) { conexion, logger in
                    _ = try await conexion.ejecutar("INSERT INTO tamano (nombre) VALUES ('sin firma')", logger)
                }
            }

            // La auditoría recoge el cambio con su autor.
            let historial = try await RepositorioAuditoria(db: db).historial(tabla: "usuario", registro: id)
            #expect(historial.contains { $0.accion == .cambio && $0.camposCambiados.contains { $0.campo == "nombre" } })
        }
    }

    @Test func configuracion() async throws {
        let id = try await conBase(try EntornoPruebas.propietario()) { db in
            try await RepositorioUsuarios(db: db).crear(
                nombre: "Config \(UUID().uuidString.prefix(6))", rol: .titular, pin: "5678", por: 1)
        }
        try await conBase(try EntornoPruebas.app()) { db in
            let repo = RepositorioConfiguracion(db: db)
            try await repo.guardar([
                .tiendaNombre: ValoresConfiguracion.codificar("Foto Prueba"),
                .sesionBloqueoMinutos: ValoresConfiguracion.codificar(15),
            ], por: id)
            let valores = try await repo.valores()
            #expect(valores.texto(.tiendaNombre) == "Foto Prueba")
            #expect(valores.politicaBloqueo.minutos == 15)
            #expect(valores.texto(.reciboTextoPie) != nil)   // viene del seed
        }
    }

    /// Criterio fase 2: dos Macs crean pedidos a la vez sin repetir número.
    @Test func numeracionConDosConexionesALaVez() async throws {
        let (usuario, cliente, tipo) = try await conBase(try EntornoPruebas.propietario()) { db in
            let usuario = try await RepositorioUsuarios(db: db).crear(
                nombre: "Numeración \(UUID().uuidString.prefix(6))", rol: .titular, pin: "1111", por: 1)
            return try await db.transaccion(usuario: usuario) { conexion, logger in
                let cliente = try await conexion
                    .ejecutar("INSERT INTO cliente (nombre) VALUES ('Cliente numeración') RETURNING id", logger)
                    .first!.decode(Int64.self)
                let tipo = try await conexion
                    .ejecutar("INSERT INTO tipo_trabajo (nombre) VALUES (\("TT \(UUID().uuidString.prefix(6))")) RETURNING id", logger)
                    .first!.decode(Int64.self)
                return (usuario, cliente, tipo)
            }
        }

        let porMac = 20
        try await withThrowingTaskGroup(of: Void.self) { grupo in
            for _ in 0..<2 {
                grupo.addTask {
                    try await conBase(try EntornoPruebas.app()) { db in
                        for _ in 0..<porMac {
                            try await db.transaccion(usuario: usuario) { conexion, logger in
                                _ = try await conexion.ejecutar("""
                                    INSERT INTO pedido (cliente_id, tipo_trabajo_id, fecha)
                                    VALUES (\(cliente), \(tipo), DATE '2030-06-01')
                                    """, logger)
                            }
                        }
                    }
                }
            }
            try await grupo.waitForAll()
        }

        try await conBase(try EntornoPruebas.app()) { db in
            let (total, distintos) = try await db.leer { conexion, logger in
                try await conexion.ejecutar(
                    "SELECT count(*), count(DISTINCT numero) FROM pedido WHERE cliente_id = \(cliente)", logger)
                    .first!.decode((Int64, Int64).self)
            }
            #expect(total == Int64(2 * porMac))
            #expect(distintos == total)
        }
    }

    /// Las pruebas SQL de Database/tests (reglas del apartado 4).
    @Test func pruebasSQLDeReglas() async throws {
        let sql = try String(
            contentsOf: Rutas.repositorio.appendingPathComponent("Database/tests/reglas_fase1_2.sql"),
            encoding: .utf8)
        try await conBase(try EntornoPruebas.propietario()) { db in
            try await db.leer { conexion, logger in
                try await conexion.ejecutar("BEGIN", logger)
                for sentencia in ScriptSQL.sentencias(sql) {
                    try await conexion.ejecutar(PostgresQuery(unsafeSQL: sentencia), logger)
                }
            }
        }
    }
}
