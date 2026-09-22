import AppKit

/**
 * LA PUERTA AGÉNTICA — el canal de doble vía entre Levy y la app (24 ago 2026).
 *
 * Nació de una mañana medida: Levy escribió 6 versiones de lienzos por REST y
 * cada una exigió matar y relanzar la app para que el espejo se enterara. El
 * AI-first ("Levy escribe, Daniel mira") no funciona si el espejo solo mira al
 * arrancar.
 *
 * Dos archivos en `~/.config/sfmap/`:
 *
 * - `orden.json` (Levy → app): `{"abrir": "<page_id>", "centrar": "<element_id>",
 *   "doc": "<ruta/relativa/al/repo.md>"}`.
 *   La app lo CONSUME (lo borra al leerlo) y aplica: navega a la página, centra+
 *   selecciona el elemento y/o abre el documento en el panel. Es el "te lo marqué
 *   en el lienzo" y el "ábreme ese SOP" — Daniel no busca el nodo y lo pulsa: se
 *   lo dice a Levy y le aparece (Regla de Oro #5, la UI es espejo, no cabina).
 * - `seleccion.json` (app → Levy): la selección actual de Daniel, con página y
 *   un resumen de cada elemento. Es el "esto que tengo marcado" — el
 *   browser_pick del lienzo.
 *
 * Es un SONDEO sobre archivos, no un socket, por la misma razón que
 * `Nube.version` es un sondeo: un canal que se ve sano cuando está muerto es
 * peor que una latencia de un segundo, visible y honesta.
 */
enum Puente {
    static var dir: URL {
        if Nube.esLocal { return Nube.directorioLocal.appendingPathComponent("Puente") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/sfmap")
    }
    static var ordenURL: URL { dir.appendingPathComponent("orden.json") }
    static var seleccionURL: URL { dir.appendingPathComponent("seleccion.json") }

    struct Orden { var abrir: String?; var centrar: String?; var doc: String?; var enfocar: String?; var ficha: String?; var embed: String?; var zoom: Double? = nil; var tareasVista: String? = nil }

    /// Lee y CONSUME la orden pendiente. Borrar antes de aplicar evita el loop
    /// de una orden que falla y se reintenta para siempre.
    static func leerOrden() -> Orden? {
        guard let d = try? Data(contentsOf: ordenURL) else { return nil }
        try? FileManager.default.removeItem(at: ordenURL)
        guard let j = try? JSONDecoder().decode(Json.self, from: d) else { return nil }
        let o = Orden(abrir: j["abrir"]?.s, centrar: j["centrar"]?.s, doc: j["doc"]?.s, enfocar: j["enfocar"]?.s, ficha: j["ficha"]?.s, embed: j["embed"]?.s, zoom: j["zoom"]?.d, tareasVista:j["tareasVista"]?.s)
        return (o.abrir == nil && o.centrar == nil && o.doc == nil && o.enfocar == nil && o.ficha == nil && o.embed == nil) ? nil : o
    }

    /// La selección de Daniel, para que Levy sepa de qué habla "esto".
    static func escribirSeleccion(pagina: String, nombre: String, elementos: [Elemento]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let j: Json = .objeto([
            "ts": .texto(ISO8601DateFormatter().string(from: Date())),
            "page_id": .texto(pagina),
            "page_name": .texto(nombre),
            "ids": .lista(elementos.map { .texto($0.id) }),
            "elementos": .lista(elementos.map { .objeto(resumen($0)) }),
        ])
        if let d = try? JSONEncoder().encode(j) { try? d.write(to: seleccionURL) }
    }

    /// Lo que un agente necesita para reconocer un elemento sin traerse el JSON entero.
    static func resumen(_ e: Elemento) -> [String: Json] {
        var r: [String: Json] = ["id": .texto(e.id), "tipo": .texto(e.tipo)]
        if e.tipo == "shape" { r["rol"] = .texto(e.rol); r["forma"] = .texto(e.figura) }
        let t = e.textoEditable
        if !t.isEmpty { r["titulo"] = .texto(String(t.prefix(120))) }
        if e.tipo == "frame", let ti = e.titulo { r["titulo"] = .texto(ti) }
        for k in ["name", "link", "evidence", "relation", "decision"] { if let v=e.crudo[k] { r[k]=v } }
        return r
    }

    /// ¿Procede recargar la página abierta con la versión del servidor?
    /// La mano de Daniel SIEMPRE gana: con cambios sin guardar, guardado en
    /// vuelo o un botón del ratón presionado, no se recarga.
    static func debeRecargar(remota: Double?, local: Double, sucio: Bool,
                             guardando: Bool, botonesRaton: Int) -> Bool {
        guard let r = remota else { return false }
        return r > local && !sucio && !guardando && botonesRaton == 0
    }

    /// Firma barata de las listas del panel: si cambia, el panel se refresca.
    static func firmaListas(_ ps: [ResumenPagina], _ cs: [Carpeta]) -> String {
        (ps.map { "\($0.id)|\($0.nombre)|\($0.folderId ?? "")" }
         + cs.map { "\($0.id)|\($0.nombre)|\($0.madre ?? "")" }).joined(separator: "·")
    }
}

extension Camara {
    /// La cámara que deja una caja en el CENTRO de la vista, conservando zoom.
    static func centradaEn(_ caja: CGRect, zoom: Double) -> Camara {
        Camara(x: caja.midX, y: caja.midY, zoom: zoom)
    }
}
