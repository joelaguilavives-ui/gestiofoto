import Foundation

/// Claves de la tabla `configuracion` (ver Database/seed/seed.sql).
public enum ClaveConfiguracion: String, Sendable, CaseIterable {
    case tiendaNombre = "tienda.nombre"
    case tiendaNIF = "tienda.nif"
    case tiendaDireccion = "tienda.direccion"
    case tiendaIBAN = "tienda.iban"
    case reciboTextoPie = "recibo.texto_pie"
    case presupuestoValidezDias = "presupuesto.validez_dias"
    case sesionBloqueoMinutos = "sesion.bloqueo_minutos"
    case pedidosCarpetasRaiz = "pedidos.carpetas_raiz"
    case laboratorioEtiquetaEnviado = "laboratorio.etiqueta_enviado"
    case laboratorioEtiquetaRecibido = "laboratorio.etiqueta_recibido"
    case mensajesPedidoListo = "mensajes.pedido_listo"
    case copiasCarpeta = "copias.carpeta"
    case copiasHora = "copias.hora"
    case copiasConservarDiarias = "copias.conservar_diarias"
    case copiasConservarMensuales = "copias.conservar_mensuales"
    /// Segundos desde 1970 de la última copia correcta (lo escribe backup.sh).
    case copiasUltima = "copias.ultima"
    case copiasUltimoError = "copias.ultimo_error"
}

/// Valores de configuración guardados como JSON (`jsonb`) en la base de datos.
/// Se leen como texto JSON y se convierten aquí.
public struct ValoresConfiguracion: Sendable, Equatable {
    public private(set) var json: [String: String]

    public init(json: [String: String] = [:]) {
        self.json = json
    }

    public func texto(_ clave: ClaveConfiguracion) -> String? {
        decodificar(String.self, clave)
    }

    public func entero(_ clave: ClaveConfiguracion) -> Int? {
        decodificar(Int.self, clave)
    }

    public func textos(_ clave: ClaveConfiguracion) -> [String] {
        decodificar([String].self, clave) ?? []
    }

    public func fecha(_ clave: ClaveConfiguracion) -> Date? {
        guard let segundos = decodificar(Double.self, clave) else { return nil }
        return Date(timeIntervalSince1970: segundos)
    }

    public mutating func fijar(_ clave: ClaveConfiguracion, jsonTexto: String) {
        json[clave.rawValue] = jsonTexto
    }

    private func decodificar<T: Decodable>(_ tipo: T.Type, _ clave: ClaveConfiguracion) -> T? {
        guard let texto = json[clave.rawValue], let datos = texto.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: datos)
    }

    /// Codifica un valor como JSON para guardarlo.
    public static func codificar<T: Encodable>(_ valor: T) -> String {
        guard let datos = try? JSONEncoder().encode(valor) else { return "null" }
        return String(decoding: datos, as: UTF8.self)
    }

    public var politicaBloqueo: PoliticaBloqueo {
        entero(.sesionBloqueoMinutos).map(PoliticaBloqueo.init(minutos:)) ?? .porDefecto
    }

    public func estadoCopia(ahora: Date) -> EstadoCopia {
        EstadoCopia.evaluar(ultima: fecha(.copiasUltima), ahora: ahora)
    }
}
