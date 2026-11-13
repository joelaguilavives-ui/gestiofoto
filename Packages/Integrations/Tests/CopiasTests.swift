import Foundation
import Testing
@testable import Integrations

@Suite("Configuración de copias")
struct ConfiguracionCopiasTests {
    @Test func idaYVuelta() {
        let c = ConfiguracionCopias(
            carpeta: "/Volumes/Copias Tienda/GestioFoto's", hora: 3, minuto: 30,
            conservarDiarias: 20, conservarMensuales: 6)
        let leida = ConfiguracionCopias.leer(c.texto())
        #expect(leida == c)
        #expect(leida.horaTexto == "03:30")
    }

    @Test func comillasParaBash() {
        #expect(ConfiguracionCopias.comillas("a'b") == #"'a'\''b'"#)
        #expect(ConfiguracionCopias.sinComillas(#"'a'\''b'"#) == "a'b")
        #expect(ConfiguracionCopias.sinComillas("\"x y\"") == "x y")
    }

    @Test func valoresPorDefecto() {
        let c = ConfiguracionCopias.leer("# vacío\nCARPETA='/c'\n")
        #expect(c.carpeta == "/c")
        #expect(c.hora == 2 && c.minuto == 0)
        #expect(c.conservarDiarias == 30 && c.conservarMensuales == 12)
    }

    @Test func validez() {
        #expect(!ConfiguracionCopias(carpeta: "").esValida)
        #expect(!ConfiguracionCopias(carpeta: "/c", hora: 24).esValida)
        #expect(ConfiguracionCopias(carpeta: "/c").esValida)
    }
}

@Suite("Ejecutor de procesos")
struct EjecutorProcesoTests {
    @Test func devuelveSalida() async throws {
        let salida = try await EjecutorProceso.ejecutar(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "echo hola; echo error 1>&2"])
        #expect(salida.contains("hola"))
        #expect(salida.contains("error"))
    }

    @Test func codigoDeError() async throws {
        await #expect(throws: ErrorProceso.fallo(codigo: 3, salida: "mal\n")) {
            try await EjecutorProceso.ejecutar(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo mal; exit 3"])
        }
    }

    @Test func entorno() async throws {
        let salida = try await EjecutorProceso.ejecutar(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "echo $GF_PRUEBA"], entorno: ["GF_PRUEBA": "valor"])
        #expect(salida == "valor\n")
    }
}
