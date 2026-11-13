import Foundation
import Testing
@testable import Domain

@Suite("PIN")
struct PINTests {
    @Test(arguments: ["1234", "12345", "123456", "0000"])
    func validos(pin: String) {
        #expect(PIN.esValido(pin))
    }

    @Test(arguments: ["", "123", "1234567", "12a4", "12 34", "١٢٣٤"])
    func invalidos(pin: String) {
        #expect(!PIN.esValido(pin))
    }
}

@Suite("Usuario")
struct UsuarioTests {
    @Test func bloqueo() {
        let ahora = Date(timeIntervalSince1970: 1_000_000)
        var u = Usuario(id: 2, nombre: "Ana", rol: .titular, activo: true, version: 1)
        #expect(!u.estaBloqueado(en: ahora))
        u.bloqueadoHasta = ahora.addingTimeInterval(60)
        #expect(u.estaBloqueado(en: ahora))
        #expect(!u.estaBloqueado(en: ahora.addingTimeInterval(61)))
    }
}

@Suite("Bloqueo de sesión")
struct PoliticaBloqueoTests {
    let inicio = Date(timeIntervalSince1970: 0)

    @Test func bloqueaAlCumplirElTiempo() {
        let p = PoliticaBloqueo(minutos: 10)
        #expect(!p.debeBloquear(ultimaActividad: inicio, ahora: inicio.addingTimeInterval(599)))
        #expect(p.debeBloquear(ultimaActividad: inicio, ahora: inicio.addingTimeInterval(600)))
    }

    @Test func ceroNoBloqueaNunca() {
        let p = PoliticaBloqueo(minutos: 0)
        #expect(!p.debeBloquear(ultimaActividad: inicio, ahora: inicio.addingTimeInterval(86_400)))
    }

    @Test func negativoEsCero() {
        #expect(PoliticaBloqueo(minutos: -5).minutos == 0)
    }
}

@Suite("Estado de la copia de seguridad")
struct EstadoCopiaTests {
    let ahora = Date(timeIntervalSince1970: 10 * 86_400)

    @Test func nunca() {
        #expect(EstadoCopia.evaluar(ultima: nil, ahora: ahora) == .nunca)
        #expect(EstadoCopia.nunca.requiereAviso)
    }

    @Test func dosDiasJustosNoAvisa() {
        let ultima = ahora.addingTimeInterval(-2 * 86_400)
        let estado = EstadoCopia.evaluar(ultima: ultima, ahora: ahora)
        #expect(estado == .reciente(ultima))
        #expect(!estado.requiereAviso)
    }

    @Test func masDeDosDiasAvisa() {
        let ultima = ahora.addingTimeInterval(-2 * 86_400 - 1)
        #expect(EstadoCopia.evaluar(ultima: ultima, ahora: ahora).requiereAviso)
    }
}

@Suite("Conexión")
struct ConexionTests {
    @Test(arguments: [
        ("mac-tienda", "mac-tienda.local"),
        ("  Mac-Tienda  ", "mac-tienda.local"),
        ("mac-tienda.local", "mac-tienda.local"),
        ("localhost", "localhost"),
        ("192.168.1.20", "192.168.1.20"),
        ("", ""),
    ])
    func normalizarServidor(entrada: String, esperado: String) {
        #expect(ConfiguracionConexion.normalizarServidor(entrada) == esperado)
    }

    @Test func verificarExigeCertificado() {
        var c = ConfiguracionConexion(servidor: "mac.local", esMacPrincipal: false, modoTLS: .verificar)
        #expect(!c.esValida)
        c.rutaCertificado = "/tmp/server.crt"
        #expect(c.esValida)
    }

    @Test func codificable() throws {
        let c = ConfiguracionConexion(servidor: "mac.local", esMacPrincipal: true)
        let datos = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(ConfiguracionConexion.self, from: datos) == c)
    }
}

@Suite("Configuración")
struct ConfiguracionTests {
    @Test func leeValoresJSON() {
        let v = ValoresConfiguracion(json: [
            "tienda.nombre": "\"Foto Joel\"",
            "sesion.bloqueo_minutos": "15",
            "pedidos.carpetas_raiz": "[\"/Volumes/NAS/Trabajos\"]",
            "copias.ultima": "86400",
            "copias.carpeta": "null",
        ])
        #expect(v.texto(.tiendaNombre) == "Foto Joel")
        #expect(v.politicaBloqueo.minutos == 15)
        #expect(v.textos(.pedidosCarpetasRaiz) == ["/Volumes/NAS/Trabajos"])
        #expect(v.fecha(.copiasUltima) == Date(timeIntervalSince1970: 86_400))
        #expect(v.texto(.copiasCarpeta) == nil)
    }

    @Test func valoresPorDefecto() {
        let v = ValoresConfiguracion()
        #expect(v.politicaBloqueo == .porDefecto)
        #expect(v.estadoCopia(ahora: Date()) == .nunca)
    }

    @Test func codificaTexto() {
        #expect(ValoresConfiguracion.codificar("No se admiten \"tarjetas\"") == #""No se admiten \"tarjetas\"""#)
        #expect(ValoresConfiguracion.codificar(10) == "10")
    }
}

@Suite("Auditoría")
struct AuditoriaTests {
    @Test func camposCambiadosSinColumnasDeControl() {
        let e = EntradaAuditoria(
            id: 1, tabla: "usuario", registroId: 2, accion: .cambio, usuario: "Ana",
            fecha: Date(),
            antes: #"{"id":2,"nombre":"Ana","activo":true,"version":1}"#,
            despues: #"{"id":2,"nombre":"Ana María","activo":true,"version":2}"#
        )
        #expect(e.camposCambiados.map(\.campo) == ["nombre"])
        #expect(e.camposCambiados.first?.despues == "Ana María")
    }
}
