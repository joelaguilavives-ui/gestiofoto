import Foundation
import Testing
@testable import Persistence

@Suite("Divisor de scripts SQL")
struct ScriptSQLTests {
    @Test func sentenciasSimples() {
        #expect(ScriptSQL.sentencias("SELECT 1; SELECT 2;\n\n") == ["SELECT 1", "SELECT 2"])
    }

    @Test func puntoYComaDentroDeCadenas() {
        let sql = "INSERT INTO t VALUES ('a;b', 'it''s; ok'); SELECT \"raro;nombre\" FROM t"
        #expect(ScriptSQL.sentencias(sql) == [
            "INSERT INTO t VALUES ('a;b', 'it''s; ok')",
            "SELECT \"raro;nombre\" FROM t",
        ])
    }

    @Test func cadenaConBarras() {
        let sql = #"SELECT E'a\';b'; SELECT 2"#
        #expect(ScriptSQL.sentencias(sql) == [#"SELECT E'a\';b'"#, "SELECT 2"])
    }

    @Test func cuerposConDolar() {
        let sql = """
            CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$
            BEGIN
              PERFORM 1; -- comentario; dentro
              RAISE NOTICE 'x;y';
            END $$;
            DO $f$ BEGIN EXECUTE format($q$SELECT 1;$q$); END $f$;
            SELECT $1, a$b FROM t;
            """
        let s = ScriptSQL.sentencias(sql)
        #expect(s.count == 3)
        #expect(s[0].hasSuffix("END $$"))
        #expect(s[0].contains("-- comentario; dentro"))
        #expect(s[1] == "DO $f$ BEGIN EXECUTE format($q$SELECT 1;$q$); END $f$")
        #expect(s[2] == "SELECT $1, a$b FROM t")
    }

    @Test func comentariosFueraSeDescartan() {
        let sql = """
            -- cabecera; con punto y coma
            /* bloque; /* anidado; */ fin */
            SELECT 1; -- final
            """
        #expect(ScriptSQL.sentencias(sql) == ["SELECT 1"])
    }

    /// Las migraciones reales se dividen sin dejar un $$ abierto.
    @Test func migracionesDelRepositorio() throws {
        let carpeta = Rutas.repositorio.appendingPathComponent("Database/migrations")
        let migraciones = try Migracion.cargar(desde: carpeta)
        #expect(migraciones.map(\.version) == Array(1...migraciones.count))
        for m in migraciones {
            let sentencias = ScriptSQL.sentencias(m.sql)
            #expect(sentencias.count > 10, "\(m.nombre)")
            for s in sentencias {
                #expect(s.components(separatedBy: "$$").count % 2 == 1, "$$ sin cerrar en \(m.nombre): \(s.prefix(80))")
            }
        }
    }
}

enum Rutas {
    /// Raíz del repositorio a partir de este fichero (Packages/Persistence/Tests/…).
    static let repositorio: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // Persistence
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // raíz
}
