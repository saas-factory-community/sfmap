import Foundation
import CoreGraphics

/// El elemento del lienzo: su JSON crudo, con accesos tipados encima.
///
/// La verdad vive en `crudo`. Los accesores no COPIAN el dato, lo LEEN — así no
/// puede existir un estado donde la struct y el JSON discrepan, que es la
/// familia de fallos donde alguien mueve un elemento y el JSON guardado sigue
/// diciendo la posición anterior.
struct Elemento {
    var crudo: Json

    init(_ j: Json) { crudo = j }

    var id: String { crudo["id"]?.s ?? "" }
    var tipo: String { crudo["type"]?.s ?? "?" }
    var x: Double { crudo["x"]?.num ?? 0 }
    var y: Double { crudo["y"]?.num ?? 0 }
    var ancho: Double { crudo["width"]?.num ?? 0 }
    var alto: Double { crudo["height"]?.num ?? 0 }
    var giro: Double { crudo["rotation"]?.num ?? 0 }
    var z: Double { crudo["zIndex"]?.num ?? 0 }
    var opacidad: Double { crudo["opacity"]?.num ?? 1 }
    var bloqueado: Bool { crudo["locked"]?.b ?? false }
    var rol: String { crudo["role"]?.s ?? "card" }
    var figura: String { crudo["shape"]?.s ?? "rect" }
    var enlace: String? { crudo["link"]?.s }
    /// Opt-in por elemento: clic quieto navega; arrastre y selección múltiple
    /// conservan su gesto. Los documentos anteriores mantienen el doble clic.
    var abreAlClic: Bool { crudo["openOnClick"]?.b ?? false }
    var grupo: String? { crudo["groupId"]?.s }
    var fijado: Bool { crudo["origin"]?["pinned"]?.b ?? false }
    var compilado: Bool { crudo["origin"] != nil }

    var caja: CGRect { CGRect(x: x, y: y, width: ancho, height: alto) }

    /// La caja que el OJO ve: incluye el pie, que cuelga fuera del rectángulo.
    /// Encuadrar y exportar usan esta, no `caja` — lo contrario corta las
    /// descripciones, que fue un fallo medido en el lienzo web.
    var cajaVisual: CGRect {
        guard tipo == "shape", let partes = textoLigado, !partes.isEmpty else { return caja }
        var r = caja
        for p in partes {
            r = r.union(CGRect(x: x + p.x, y: y + p.y, width: p.ancho, height: p.alto))
        }
        return r
    }

    // ── texto ligado (figuras) ─────────────────────────────────────────────
    struct Parte {
        var kind: String, texto: String, lineas: [String]
        var x: Double, y: Double, ancho: Double, alto: Double
        var estilo: Estilo
    }
    /// El estilo vive en `Texto.swift`: lo comparten el modelo, el medidor y el
    /// pintor. Un tipo por capa seria el camino directo a medir una cosa y
    /// pintar otra.
    typealias Estilo = EstiloTexto

    var textoLigado: [Parte]? {
        guard tipo == "shape", let l = crudo["text"]?.arr else { return nil }
        return l.map { p in
            Parte(kind: p["kind"]?.s ?? "title",
                  texto: p["text"]?.s ?? "",
                  lineas: p["lines"]?.arr?.compactMap { $0.s } ?? [],
                  x: p["x"]?.num ?? 0, y: p["y"]?.num ?? 0,
                  ancho: p["width"]?.num ?? 0, alto: p["height"]?.num ?? 0,
                  estilo: Estilo(p["style"]))
        }
    }

    /// Alineación del texto de una figura. La MISMA regla que el lienzo web:
    /// compilado a la izquierda (el compositor lo colocó a propósito), de la
    /// mano al centro (una figura rotulada quiere su etiqueta en medio).
    var alineacion: String {
        if let a = crudo["textAlign"]?.s { return a }
        if tipo == "text" { return crudo["align"]?.s ?? "left" }
        // El CÓDIGO se alinea a la izquierda siempre: centrarlo rompe la
        // sangría, que en un bloque de código es información.
        if tipo == "code" { return "left" }
        return compilado ? "left" : "center"
    }

    // ── bloque de texto libre ──────────────────────────────────────────────
    var textoLibre: String? { tipo == "text" ? crudo["text"]?.s : nil }
    var lineas: [String] { crudo["lines"]?.arr?.compactMap { $0.s } ?? [] }
    var estilo: Estilo { Estilo(crudo["style"]) }

    // ── tinta ──────────────────────────────────────────────────────────────
    var trazoPuntos: [(x: Double, y: Double, p: Double)] {
        crudo["points"]?.arr?.map { (($0["x"]?.num ?? 0), ($0["y"]?.num ?? 0), ($0["pressure"]?.num ?? 0.5)) } ?? []
    }

    /// Los puntos con TODO lo que la pluma sabe decir. `tiltX`, `tiltY` y `t`
    /// son campos ADITIVOS: el lienzo web no los conoce, los ignora al pintar y
    /// los conserva al guardar, y un trazo viejo que no los trae sale igual de
    /// bien porque el motor los trata como "sin dato", no como cero.
    var trazoTinta: [PuntoTinta] {
        crudo["points"]?.arr?.map { j in
            PuntoTinta(x: j["x"]?.num ?? 0, y: j["y"]?.num ?? 0,
                       p: j["pressure"]?.num ?? 0.5,
                       ix: j["tiltX"]?.num ?? 0, iy: j["tiltY"]?.num ?? 0,
                       t: j["t"]?.num ?? -1)
        } ?? []
    }

    /// La clave de caché del contorno. Cambia cuando cambia lo que DIBUJA el
    /// trazo y no cuando cambia dónde está: `updatedAt` se mueve con cualquier
    /// edición, así que mover un trazo lo recalcularía sin necesidad — por eso
    /// el camino se guarda en coordenadas locales y la posición no entra aquí.
    var claveTinta: String {
        "\(id)|\(crudo["updatedAt"]?.num ?? 0)|\(grosorTinta)|\(esMarcador)|\(crudo["points"]?.arr?.count ?? 0)"
    }
    var grosorTinta: Double { crudo["size"]?.num ?? 4 }
    var esMarcador: Bool { crudo["highlighter"]?.b ?? false }
    var colorTinta: String? { crudo["color"]?.s }

    // ── conector ───────────────────────────────────────────────────────────
    var desdeId: String? { crudo["fromId"]?.s }
    var hastaId: String? { crudo["toId"]?.s }
    var ruta: [CGPoint] {
        crudo["points"]?.arr?.map { CGPoint(x: $0["x"]?.num ?? 0, y: $0["y"]?.num ?? 0) } ?? []
    }
    var claseArista: String { crudo["kind"]?.s ?? "flujo" }
    var puntaFin: String { crudo["headEnd"]?.s ?? ((crudo["arrowEnd"]?.b ?? true) ? "flecha" : "ninguna") }
    var puntaInicio: String { crudo["headStart"]?.s ?? "ninguna" }
    var ruteo: String { crudo["routing"]?.s ?? "ortogonal" }
    var etiqueta: String? { crudo["label"]?.s }

    // ── sección ────────────────────────────────────────────────────────────
    var titulo: String? { crudo["title"]?.s }
    var tinte: String { crudo["tint"]?.s ?? "neutro" }

    /// El TERRITORIO de una FIGURA (no de una sección): `tint` sobre un `shape`.
    /// Es lo que permite dibujar la forma de un sistema —un embudo, un reloj de
    /// arena— con un color que el TEMA resuelve, en vez de un literal que solo
    /// sirve en el tema donde se escribió. Ver `Tema.relleno`.
    var territorio: String? { tipo == "shape" ? crudo["tint"]?.s : nil }

    // ── colores y trazo elegidos a mano ────────────────────────────────────
    var colorExplicito: Bool { crudo["color"]?["explicit"]?.b ?? false }
    var relleno: String? { colorExplicito ? crudo["color"]?["fill"]?.s : nil }
    var contorno: String? { colorExplicito ? crudo["color"]?["stroke"]?.s : nil }
    var colorTexto: String? { colorExplicito ? crudo["color"]?["text"]?.s : nil }
    var resaltado: String? { colorExplicito ? crudo["color"]?["highlight"]?.s : nil }
    var trazoExplicito: Bool { crudo["trazo"]?["explicit"]?.b ?? false }
    var estiloLinea: String? { trazoExplicito ? crudo["trazo"]?["style"]?.s : nil }
    var grosorLinea: Double? { trazoExplicito ? crudo["trazo"]?["width"]?.num : nil }
    var radioEsquina: Double? { trazoExplicito ? crudo["trazo"]?["radius"]?.num : nil }

    /// Mover conserva TODO lo demás del JSON, incluidos los campos que sfmap
    /// no conoce. Es el punto donde la promesa de `Json.con` se cumple.
    ///
    /// ⚠️ Y **FIJA** lo compilado. No es un detalle: el documento tiene dos
    /// capas, y el contrato entre ellas es que cuando la mano toca algo que
    /// produjo el compilador, ese elemento queda `pinned` y el compilador deja
    /// de mandarlo (aunque lo sigue viendo como obstáculo).
    ///
    /// sfmap movía SIN fijar. Nada fallaba: el elemento se movía, se guardaba,
    /// todo verde. Y el siguiente `compileRegion` lo devolvía a su sitio
    /// borrando la decisión de Daniel, sin aviso. La regla vive en el web desde
    /// el día uno; que una segunda superficie escriba el mismo documento y NO
    /// la respete es peor que no tener la regla, porque el mismo gesto tiene
    /// dos significados según la ventana en la que lo hagas.
    mutating func mover(dx: Double, dy: Double) {
        tocar(["x": .numero(x + dx), "y": .numero(y + dy)])
    }
}


struct Camara {
    var x: Double = 0, y: Double = 0, zoom: Double = 1
}

struct ResumenPagina: Identifiable {
    var id: String, nombre: String
    var folderId: String?
    var elementos: Int
}
/// Una carpeta. `madre` permite UN nivel de anidamiento y solo uno: una
/// carpeta con madre no puede ser madre de nadie. Daniel: *"solo un nivel de
/// profundidad, no necesito más"* — y el limite es una decision, no una
/// carencia: dos niveles ya obligan a recordar donde guardaste algo.
struct Carpeta: Identifiable { var id: String, nombre: String; var madre: String? = nil }
