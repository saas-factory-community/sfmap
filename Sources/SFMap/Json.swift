import Foundation

/// Un valor JSON cualquiera, para poder CONSERVAR lo que no se entiende.
///
/// ⚠️ Esto no es comodidad, es la condición para que sfmap pueda escribir en el
/// mismo documento que el lienzo web sin destruirlo.
///
/// El modelo de allá crece: hoy tiene `regions`, `trazo`, `fromPort`. Si sfmap
/// decodificara a una struct cerrada y volviera a serializar, cada campo que
/// aún no conoce desaparecería al guardar — sin error y sin aviso. Es
/// exactamente cómo el v3 vació la capa `regions` de una página: un guardado
/// parcial que pisa lo que no conoce.
///
/// Aquí el elemento guarda su JSON CRUDO y al escribir se re-emite entero, con
/// solo los campos que sfmap tocó sobreescritos encima.
indirect enum Json: Codable, Equatable {
    case nulo
    case bool(Bool)
    case numero(Double)
    case texto(String)
    case lista([Json])
    case objeto([String: Json])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .nulo }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .numero(v) }
        else if let v = try? c.decode(String.self) { self = .texto(v) }
        else if let v = try? c.decode([Json].self) { self = .lista(v) }
        else if let v = try? c.decode([String: Json].self) { self = .objeto(v) }
        else { self = .nulo }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .nulo:            try c.encodeNil()
        case .bool(let v):     try c.encode(v)
        case .numero(let v):   try c.encode(v)
        case .texto(let v):    try c.encode(v)
        case .lista(let v):    try c.encode(v)
        case .objeto(let v):   try c.encode(v)
        }
    }

    // ── lectura cómoda ──────────────────────────────────────────────────────
    subscript(_ k: String) -> Json? {
        if case .objeto(let o) = self { return o[k] }
        return nil
    }
    var d: Double? { if case .numero(let v) = self { return v }; return nil }
    var s: String? { if case .texto(let v) = self { return v }; return nil }
    var b: Bool? { if case .bool(let v) = self { return v }; return nil }
    var arr: [Json]? { if case .lista(let v) = self { return v }; return nil }
    var obj: [String: Json]? { if case .objeto(let o) = self { return o }; return nil }

    /// Número tolerante: el documento mezcla enteros y decimales, y algunos
    /// campos llegan como cadena desde versiones viejas.
    var num: Double? { d ?? (s.flatMap(Double.init)) }

    /// Escribe una clave conservando todo lo demás. Es la operación que hace
    /// que guardar no sea destructivo.
    func con(_ k: String, _ v: Json?) -> Json {
        var o = obj ?? [:]
        if let v { o[k] = v } else { o.removeValue(forKey: k) }
        return .objeto(o)
    }
    func con(_ pares: [String: Json?]) -> Json {
        var o = obj ?? [:]
        for (k, v) in pares { if let v { o[k] = v } else { o.removeValue(forKey: k) } }
        return .objeto(o)
    }
}
