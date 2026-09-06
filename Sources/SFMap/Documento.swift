import CoreGraphics
import Foundation

/**
 * EL HISTORIAL. Una accion = una entrada, aunque toque 200 elementos.
 *
 * Recompilar una region mueve decenas de cajas y debe deshacerse de UNA vez,
 * con una etiqueta que diga que fue: "recompilar" y no 200 pasos anonimos.
 *
 * Se guardan PARCHES (que cambio), no fotos del documento entero: con 200
 * elementos, esa diferencia es la que decide si el historial cabe en memoria.
 */
struct Parche {
    var agregados: [Elemento] = []
    var antes: [Elemento] = []
    var despues: [Elemento] = []
    var quitados: [Elemento] = []

    var vacio: Bool { agregados.isEmpty && antes.isEmpty && quitados.isEmpty }
}

/// Deriva el parche entre dos estados. La identidad es el ID, no la posicion.
func diferencia(_ previo: [Elemento], _ nuevo: [Elemento]) -> Parche {
    let antesPorId = Dictionary(previo.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let despuesPorId = Dictionary(nuevo.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var p = Parche()
    for e in nuevo {
        guard let viejo = antesPorId[e.id] else { p.agregados.append(e); continue }
        if viejo.crudo != e.crudo { p.antes.append(viejo); p.despues.append(e) }
    }
    for e in previo where despuesPorId[e.id] == nil { p.quitados.append(e) }
    return p
}

private func aplicar(_ els: [Elemento], quitar: [Elemento], poner: [Elemento]) -> [Elemento] {
    let fuera = Set(quitar.map(\.id))
    var pendientes = Dictionary(poner.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var out: [Elemento] = []
    for e in els {
        if fuera.contains(e.id) { continue }
        if let r = pendientes.removeValue(forKey: e.id) { out.append(r); continue }
        out.append(e)
    }
    out.append(contentsOf: pendientes.values)
    return out
}

final class Historial {
    private var atras: [(etiqueta: String, parche: Parche)] = []
    private var adelante: [(etiqueta: String, parche: Parche)] = []
    private let tope = 200

    var puedeDeshacer: Bool { !atras.isEmpty }
    var puedeRehacer: Bool { !adelante.isEmpty }
    var etiquetaSiguiente: String? { atras.last?.etiqueta }

    /// Registra un cambio YA aplicado. Devuelve false si no cambio nada.
    @discardableResult
    func registrar(_ etiqueta: String, _ previo: [Elemento], _ nuevo: [Elemento]) -> Bool {
        let p = diferencia(previo, nuevo)
        guard !p.vacio else { return false }
        atras.append((etiqueta, p))
        if atras.count > tope { atras.removeFirst() }
        // Una accion nueva invalida el futuro: rehacer despues de editar daria
        // un estado que nunca existio.
        adelante.removeAll()
        return true
    }

    func deshacer(_ els: [Elemento]) -> (elementos: [Elemento], etiqueta: String)? {
        guard let e = atras.popLast() else { return nil }
        adelante.append(e)
        return (aplicar(els, quitar: e.parche.agregados, poner: e.parche.antes + e.parche.quitados), e.etiqueta)
    }

    func rehacer(_ els: [Elemento]) -> (elementos: [Elemento], etiqueta: String)? {
        guard let e = adelante.popLast() else { return nil }
        atras.append(e)
        return (aplicar(els, quitar: e.parche.quitados, poner: e.parche.despues + e.parche.agregados), e.etiqueta)
    }

    func limpiar() { atras.removeAll(); adelante.removeAll() }
}

/**
 * EL DOCUMENTO. El estado del lienzo y las operaciones sobre el.
 *
 * Todo cambio pasa por `editar`, que registra el historial. Un GESTO continuo
 * —arrastrar una figura, mover un deslizador— se abre con `abrirGesto` y se
 * cierra con `cerrarGesto`: en medio hay decenas de cambios y el historial ve
 * UNO.
 *
 * ⚠️ Sin eso, arrastrar el grosor de 1.5 a 6 dejaba DIEZ entradas y un deshacer
 * retrocedia un escalon. Es la misma clase de fallo que arrastrar una figura ya
 * habia tenido, sin aplicar en la superficie nueva.
 */
final class Documento {
    private(set) var elementos: [Elemento] = []
    var seleccion: Set<String> = []
    let historial = Historial()
    /// Avisa de que el documento cambio, para repintar y marcar sucio.
    var alCambiar: ((_ persistente: Bool) -> Void)?

    private var gestoAbierto: [Elemento]?

    /**
     * Cargar elementos. `recarga` = es LA MISMA página que ya estaba abierta,
     * releída porque cambió en otro sitio.
     *
     * ⚠️ EL DESHACER QUE DEJABA DE DESHACER (26 ago 2026).
     *
     * Daniel borró unos elementos, el generador escribió la página desde el
     * otro lado, la app se enteró y la recargó sola — y a partir de ahí ⌘Z no
     * recuperaba nada: *"el comando zeta no funcionó, ahorita lo presiono y ya
     * no recupero algo que eliminé"*. No había bug en el historial: había un
     * `limpiar()` en el camino de la recarga. Un sondeo de fondo que nadie
     * pidió le vaciaba la historia por debajo.
     *
     * En una recarga el historial SE QUEDA, y la selección también. Puede
     * hacerlo porque el historial guarda PARCHES por id, no fotos de la
     * página entera: deshacer "eliminar" repone esos elementos aunque el resto
     * del lienzo haya cambiado alrededor. Solo un cambio de página de verdad
     * —abrir otro lienzo— empieza de cero, porque ahí la historia no habla de
     * lo que hay en pantalla.
     */
    func cargar(_ els: [Elemento], recarga: Bool = false) {
        elementos = els
        if recarga {
            seleccion = seleccion.filter { id in els.contains { $0.id == id } }
        } else {
            seleccion = []
            historial.limpiar()
        }
        gestoAbierto = nil
    }

    func porId(_ id: String) -> Elemento? { elementos.first { $0.id == id } }
    var seleccionados: [Elemento] { elementos.filter { seleccion.contains($0.id) } }

    /// El siguiente z para algo nuevo. Encima de todo lo que ya hay.
    var zSiguiente: Double { (elementos.map(\.z).max() ?? 0) + 1 }

    // ── el unico camino de escritura ────────────────────────────────────────

    /// Aplica un cambio y lo registra como UNA entrada del historial.
    func editar(_ etiqueta: String, _ cuerpo: (inout [Elemento]) -> Void) {
        let previo = elementos
        cuerpo(&elementos)
        if gestoAbierto == nil {
            _ = historial.registrar(etiqueta, previo, elementos)
        }
        alCambiar?(true)
    }

    /// Abre un gesto continuo. Los cambios de dentro se colapsan en uno.
    func abrirGesto() {
        guard gestoAbierto == nil else { return }
        gestoAbierto = elementos
    }

    /**
     * ⛔ EL FALLO QUE SE COMIÓ UN DÍA ENTERO DE TRABAJO DE DANIEL (26 ago 2026).
     *
     * Esta función registraba el paso de deshacer y **no avisaba de que el
     * documento había cambiado**. Y como los cambios de DENTRO del gesto van
     * por `volatil` —que avisa con `persistente: false` a propósito, para no
     * guardar en cada fotograma del arrastre—, el resultado era que **mover,
     * redimensionar, girar o doblar algo con el ratón NUNCA marcaba sucio**.
     *
     * Nada fallaba a la vista: la figura se movía, se quedaba donde la
     * soltabas, el lienzo se repintaba y la barra seguía diciendo "guardado".
     * Solo se veía al volver: *"los logos los centro y el cuadro de
     * inteligencia lo cubro de blanco, regreso y vuelve a estar así"*. Cada
     * arrastre del día se perdía en cuanto la página se releía o se relanzaba
     * la app — y como el trabajo de colocar un lienzo es CASI TODO arrastres,
     * se perdía casi todo.
     *
     * Que `registrar` devuelva si hubo cambio real no es adorno: un gesto que
     * no movió nada (pulsar y soltar sin arrastrar) no debe marcar sucio ni
     * gastar un paso de deshacer.
     */
    func cerrarGesto(_ etiqueta: String) {
        guard let previo = gestoAbierto else { return }
        gestoAbierto = nil
        if historial.registrar(etiqueta, previo, elementos) { alCambiar?(true) }
    }

    /// Cambio VOLATIL: no toca el historial ni marca sucio. Lo usa el ruteo en
    /// vivo durante un arrastre, que se re-hara al soltar de todos modos.
    func volatil(_ cuerpo: (inout [Elemento]) -> Void) {
        cuerpo(&elementos)
        alCambiar?(false)
    }

    func deshacer() {
        guard let r = historial.deshacer(elementos) else { return }
        elementos = r.elementos
        seleccion = seleccion.filter { id in elementos.contains { $0.id == id } }
        alCambiar?(true)
    }

    func rehacer() {
        guard let r = historial.rehacer(elementos) else { return }
        elementos = r.elementos
        seleccion = seleccion.filter { id in elementos.contains { $0.id == id } }
        alCambiar?(true)
    }

    // ── operaciones ─────────────────────────────────────────────────────────

    /// Avisa de que la SELECCION cambió. Separado de `alCambiar` porque son dos
    /// cosas distintas: una repinta y marca sucio, la otra reconstruye la barra
    /// contextual — y confundirlas deja la barra pintando la selección anterior.
    var alSeleccionar: (() -> Void)?

    func agregar(_ nuevos: [Elemento], etiqueta: String, seleccionar: Bool = true) {
        editar(etiqueta) { $0.append(contentsOf: nuevos) }
        if seleccionar {
            seleccion = Set(nuevos.map(\.id))
            // ⚠️ SIN ESTE AVISO la barra contextual no aparecía al crear.
            // Nada fallaba: la figura nacía seleccionada, con sus manijas, y sin
            // una sola herramienta para editarla — el estado más frustrante
            // posible, porque parece que la app no tiene barra.
            alSeleccionar?()
        }
    }

    /**
     * Borra la seleccion, y con ella los conectores que se quedan huerfanos.
     *
     * Un conector cuyo destino ya no existe no se puede dibujar ni arreglar: se
     * va con su extremo. Dejarlo produce exactamente el fallo del v3, donde
     * `points: []` daba un elemento invisible pero clickeable.
     */
    func borrarSeleccion() {
        guard !seleccion.isEmpty else { return }
        editar("eliminar") { els in
            // EL CANDADO MANDA. Un candado que el borrado ignora no es candado.
            let fuera = Set(els.filter { seleccion.contains($0.id) && !$0.bloqueado }.map(\.id))
            els.removeAll { fuera.contains($0.id) }
            let huerfanos = Conectores.huerfanos(els)
            els.removeAll { huerfanos.contains($0.id) }
        }
        seleccion = []
    }

    /// Duplica la seleccion, desplazada. Los conectores INTERNOS se duplican
    /// tambien y apuntan a las copias — si no, la copia sale desconectada y hay
    /// que rehacer a mano lo que ya estaba hecho.
    @discardableResult
    func duplicar(_ ids: Set<String>, desplazamiento: CGPoint = CGPoint(x: 24, y: 24)) -> [String] {
        let originales = elementos.filter { ids.contains($0.id) }
        guard !originales.isEmpty else { return [] }
        var mapa: [String: String] = [:]
        let z = zSiguiente
        for o in originales { mapa[o.id] = Crear.nuevoId(o.tipo) }

        var copias: [Elemento] = []
        for (i, o) in originales.enumerated() {
            var c = o
            c.crudo = c.crudo.con(["id": .texto(mapa[o.id]!), "zIndex": .numero(z + Double(i))])
            if o.tipo == "connector" {
                /*
                 * ⚠️ EL FILTRO SE DECIDE CON LOS IDS VIEJOS, ANTES DE RE-APUNTAR.
                 *
                 * La primera version re-apuntaba y DESPUES filtraba buscando los
                 * ids en el mapa — que esta indexado por los ids ORIGINALES. Para
                 * entonces el conector ya llevaba los nuevos, ninguno estaba en el
                 * mapa, y TODOS se descartaban: duplicar tres piezas conectadas
                 * devolvia dos y la copia salia suelta.
                 *
                 * Un conector que apunta FUERA de la seleccion si se descarta a
                 * proposito: apuntaria al original y cruzaria el lienzo entero.
                 */
                guard let d = o.desdeId, let h = o.hastaId,
                      let nd = mapa[d], let nh = mapa[h] else { continue }
                c.crudo = c.crudo.con(["fromId": .texto(nd), "toId": .texto(nh)])
            } else {
                c.mover(dx: desplazamiento.x, dy: desplazamiento.y)
            }
            copias.append(c)
        }
        editar("duplicar") { els in
            els.append(contentsOf: copias)
            els = Conectores.reruteaTodo(els)
        }
        let nuevos = copias.map(\.id)
        seleccion = Set(nuevos)
        return nuevos
    }

    /**
     * LOS CUATRO MOVIMIENTOS DE APILADO.
     *
     * ⚠️ Antes eran dos, y las dos recorrian `els.indices` — el orden del
     * ARRAY— repartiendo z crecientes. Pero el array no esta ordenado por z, y
     * el que pinta si: mandar tres cosas al frente las devolvia apiladas en un
     * orden distinto del que tenian, sin avisar. Lo primero que hace esto es
     * ordenar por z, y a partir de ahi la aritmetica vive en `Orden`, que es
     * pura y se prueba sola.
     *
     * Y el z se REESCRIBE como enteros consecutivos en cada operacion. Sumar
     * fracciones para colar algo entre dos vecinos funciona hasta que dejan de
     * caber decimales; con un orden limpio no hay deriva que acumular.
     */
    func mover(_ m: Orden.Movimiento) {
        guard !seleccion.isEmpty else { return }
        let ordenados = elementos.sorted { $0.z < $1.z }
        guard let nuevo = Orden.reordenar(ordenados.map(\.id), seleccion: seleccion, m) else { return }
        let z = Dictionary(uniqueKeysWithValues: nuevo.enumerated().map { ($1, Double($0)) })
        editar(m.nombre) { els in
            for k in els.indices {
                guard let nz = z[els[k].id], nz != els[k].z else { continue }
                els[k].tocar(["zIndex": .numero(nz)])
            }
        }
    }

    func alFrente() { mover(.alFrente) }
    func alFondo()  { mover(.alFondo) }
    func unaAdelante() { mover(.adelante) }
    func unaAtras()    { mover(.atras) }

    func alternarCandado() {
        guard !seleccion.isEmpty else { return }
        let bloquear = !seleccionados.contains { $0.bloqueado }
        editar(bloquear ? "bloquear" : "desbloquear") { els in
            for k in els.indices where seleccion.contains(els[k].id) {
                // El candado NO fija: bloquear no es una decision sobre la
                // geometria, y fijar por bloquear sacaria del compilador algo
                // que solo se quiso proteger de un arrastre accidental.
                els[k].tocarSinFijar(["locked": .bool(bloquear)])
            }
        }
    }

    /// Mueve la seleccion respetando candados. Devuelve los ids que se movieron.
    ///
    /// `rapido` = estamos DENTRO de un gesto de arrastre y el ruteo bueno se
    /// hará al soltar. Las flechas del teclado no lo piden: mover con las
    /// flechas es un acto discreto y ahí sí se quiere la ruta definitiva.
    @discardableResult
    func mover(_ ids: Set<String>, dx: Double, dy: Double, rapido: Bool = false) -> Set<String> {
        var movidos: Set<String> = []
        volatil { els in
            for k in els.indices where ids.contains(els[k].id) {
                // EL CANDADO MANDA. Un candado que el arrastre ignora es una
                // sugerencia, no un candado.
                if els[k].bloqueado { continue }
                els[k].mover(dx: dx, dy: dy)
                movidos.insert(els[k].id)
            }
            if !movidos.isEmpty { els = Conectores.rerutear(els, movidos: movidos, rapido: rapido) }
        }
        return movidos
    }

    // ── agrupar ─────────────────────────────────────────────────────────────

    /// Todos los ids que se seleccionan al tocar UNO. Sube al grupo si lo hay.
    func expandirSeleccion(_ ids: Set<String>) -> Set<String> {
        let grupos = Set(elementos.filter { ids.contains($0.id) }.compactMap(\.grupo))
        guard !grupos.isEmpty else { return ids }
        var out = ids
        for e in elementos where e.grupo != nil && grupos.contains(e.grupo!) { out.insert(e.id) }
        return out
    }

    /// ¿La seleccion es uno o mas grupos completos?
    var esGrupo: Bool {
        let sel = seleccionados
        return sel.count > 1 && sel.allSatisfy { $0.grupo != nil }
    }

    /// Agrupa. Un elemento que ya estaba en otro grupo se MUDA al nuevo: anidar
    /// grupos suena potente y produce arboles que nadie puede deshacer sin un
    /// panel de capas, y este lienzo no lo tiene.
    func agrupar() {
        guard seleccion.count >= 2 else { return }
        let g = Crear.nuevoId("g")
        // Agrupar tambien JUNTA en el apilado: ver `Orden.juntar`. Sin esto un
        // extraño se queda atrapado entre dos miembros y viaja con el grupo
        // para siempre, partiendolo por la mitad al pintar.
        let ordenados = elementos.sorted { $0.z < $1.z }.map(\.id)
        let z = Orden.juntar(ordenados, grupo: seleccion)
            .map { Dictionary(uniqueKeysWithValues: $0.enumerated().map { ($1, Double($0)) }) }
        editar("agrupar") { els in
            for k in els.indices {
                if seleccion.contains(els[k].id) { els[k].tocarSinFijar(["groupId": .texto(g)]) }
                if let nz = z?[els[k].id], nz != els[k].z { els[k].tocar(["zIndex": .numero(nz)]) }
            }
        }
    }

    func desagrupar() {
        let grupos = Set(seleccionados.compactMap(\.grupo))
        guard !grupos.isEmpty else { return }
        editar("desagrupar") { els in
            for k in els.indices where els[k].grupo != nil && grupos.contains(els[k].grupo!) {
                els[k].tocarSinFijar(["groupId": nil])
            }
        }
    }

    /// Todos los elementos de la MISMA region compilada que uno dado.
    func regionDe(_ id: String) -> Set<String> {
        guard let r = porId(id)?.crudo["origin"]?["regionId"]?.s else { return [id] }
        return Set(elementos.filter { $0.crudo["origin"]?["regionId"]?.s == r }.map(\.id))
    }

    // ── alinear ─────────────────────────────────────────────────────────────

    func alinear(_ eje: String) {
        guard let deltas = Geo.alinear(elementos, seleccion, eje) else { return }
        editar("alinear") { els in
            for k in els.indices {
                guard let d = deltas[els[k].id], !els[k].bloqueado, d != .zero else { continue }
                els[k].mover(dx: d.x, dy: d.y)
            }
            els = Conectores.reruteaTodo(els)
        }
    }

    func distribuir(horizontal: Bool) {
        guard let deltas = Geo.distribuir(elementos, seleccion, horizontal: horizontal) else { return }
        editar("distribuir") { els in
            for k in els.indices {
                guard let d = deltas[els[k].id], !els[k].bloqueado, d != .zero else { continue }
                els[k].mover(dx: d.x, dy: d.y)
            }
            els = Conectores.reruteaTodo(els)
        }
    }

    // ── acomodar ────────────────────────────────────────────────────────────

    /**
     * ACOMODAR: colocar las figuras seleccionadas siguiendo sus flechas.
     *
     * Es un layout por CAPAS (el mismo esqueleto que dagre): rango topologico
     * sobre las aristas de la seleccion, orden dentro del rango por baricentro
     * de sus vecinos, y separacion medida con la huella VISUAL — el pie de una
     * tarjeta cuelga por debajo y si no se reserva, la fila de abajo se encima.
     *
     * QUE NO HACE, a proposito:
     *   · No toca lo BLOQUEADO. Un candado que el acomodo ignora no es candado,
     *     y como el resultado depende de ellos se DICE cuantos quedaron fuera:
     *     un acomodo que respeta un candado se ve igual que uno que no funciono.
     *   · No toca lo que no esta seleccionado. Acomodar el lienzo entero por
     *     accidente es irreversible en la practica, aunque haya deshacer.
     *   · No inventa aristas. Dos cajas sin conectar caen en columnas distintas
     *     y eso es informacion honesta, no un error.
     */
    @discardableResult
    func acomodar(direccion: String = "LR") -> (movidos: Int, bloqueados: Int) {
        let sel = seleccionados
        let nodos = sel.filter { esNodoDeLayout($0) && !$0.bloqueado }
        let bloqueados = sel.filter { esNodoDeLayout($0) && $0.bloqueado }.count
        guard nodos.count >= 2 else { return (0, bloqueados) }
        let ids = Set(nodos.map(\.id))

        // Las aristas que CUENTAN son las que unen dos nodos de la seleccion:
        // una flecha hacia afuera no puede influir en un layout que no incluye
        // su destino.
        let aristas = elementos.compactMap { e -> (String, String)? in
            guard e.tipo == "connector", let a = e.desdeId, let b = e.hastaId,
                  ids.contains(a), ids.contains(b), a != b else { return nil }
            return (a, b)
        }

        let rango = rangoTopologico(Array(ids), aristas)
        // Orden dentro del rango: por baricentro de los vecinos ya colocados. Es
        // la heuristica de reduccion de cruces de Sugiyama, en su forma minima.
        var porRango: [Int: [String]] = [:]
        for id in ids { porRango[rango[id] ?? 0, default: []].append(id) }
        let posY = Dictionary(uniqueKeysWithValues: nodos.map { ($0.id, $0.caja.midY) })
        for (r, lista) in porRango {
            porRango[r] = lista.sorted { a, b in
                let va = vecinos(a, aristas).compactMap { posY[$0] }
                let vb = vecinos(b, aristas).compactMap { posY[$0] }
                let ba = va.isEmpty ? (posY[a] ?? 0) : va.reduce(0, +) / Double(va.count)
                let bb = vb.isEmpty ? (posY[b] ?? 0) : vb.reduce(0, +) / Double(vb.count)
                return ba < bb
            }
        }

        let huella = Dictionary(uniqueKeysWithValues: nodos.map { ($0.id, $0.cajaVisual) })
        let separacionRango = 90.0, separacionNodo = 46.0
        let horizontal = direccion == "LR"
        var destino: [String: CGPoint] = [:]
        var avance = 0.0
        for r in porRango.keys.sorted() {
            let lista = porRango[r] ?? []
            let grosor = lista.compactMap { huella[$0] }
                .map { horizontal ? $0.width : $0.height }.max() ?? 0
            var cruce = 0.0
            for id in lista {
                guard let v = huella[id] else { continue }
                // Centrado dentro de su rango: una caja angosta en una fila de
                // anchas se ve descolgada si se alinea al borde.
                let centrado = (grosor - (horizontal ? v.width : v.height)) / 2
                destino[id] = horizontal
                    ? CGPoint(x: avance + centrado, y: cruce)
                    : CGPoint(x: cruce, y: avance + centrado)
                cruce += (horizontal ? v.height : v.width) + separacionNodo
            }
            avance += grosor + separacionRango
        }

        // Centro de masa ANTES, para no teletransportar el grupo al origen del
        // mundo — el peor resultado posible para un boton que promete ordenar.
        let cajaAntes = nodos.dropFirst().reduce(nodos[0].caja) { $0.union($1.caja) }
        let minX = destino.values.map(\.x).min() ?? 0
        let minY = destino.values.map(\.y).min() ?? 0
        let maxX = destino.map { $0.value.x + (huella[$0.key]?.width ?? 0) }.max() ?? 0
        let maxY = destino.map { $0.value.y + (huella[$0.key]?.height ?? 0) }.max() ?? 0
        let dx = cajaAntes.midX - (minX + maxX) / 2
        let dy = cajaAntes.midY - (minY + maxY) / 2

        var movidos = 0
        editar("acomodar") { els in
            for k in els.indices {
                guard let d = destino[els[k].id], let v = huella[els[k].id] else { continue }
                // El offset de la huella visual se descuenta: si el nodo
                // sobresale por arriba, colocar por la caja lo dejaria corrido.
                let x = (d.x + dx + (els[k].caja.minX - v.minX)).rounded()
                let y = (d.y + dy + (els[k].caja.minY - v.minY)).rounded()
                if x == els[k].x && y == els[k].y { continue }
                movidos += 1
                // Tocar un compilado lo FIJA, igual que arrastrarlo con el dedo:
                // acomodar es la mano moviendolo, aunque lo mueva un algoritmo.
                els[k].tocar(["x": .numero(x), "y": .numero(y)])
            }
            els = Conectores.reruteaTodo(els)
        }
        return (movidos, bloqueados)
    }

    /// Un elemento puede ser NODO si ocupa espacio y no es una linea.
    private func esNodoDeLayout(_ e: Elemento) -> Bool {
        ["shape", "image", "table", "code", "embed", "text"].contains(e.tipo)
    }

    private func vecinos(_ id: String, _ aristas: [(String, String)]) -> [String] {
        aristas.compactMap { $0.0 == id ? $0.1 : ($0.1 == id ? $0.0 : nil) }
    }

    /// Rango topologico por camino mas largo. Los ciclos NO cuelgan el
    /// algoritmo: la arista que cerraria el ciclo se ignora, que es lo que hace
    /// cualquier motor de layout de grafos serio.
    private func rangoTopologico(_ ids: [String], _ aristas: [(String, String)]) -> [String: Int] {
        var salientes: [String: [String]] = [:]
        var grado: [String: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for (a, b) in aristas {
            salientes[a, default: []].append(b)
            grado[b, default: 0] += 1
        }
        var rango: [String: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        var cola = ids.filter { grado[$0] == 0 }
        // Sin raices (todo el grafo es un ciclo) se arranca por el primero: un
        // orden arbitrario pero estable es mejor que no colocar nada.
        if cola.isEmpty, let primero = ids.first { cola = [primero]; grado[primero] = 0 }
        var vistos = Set<String>()
        while let n = cola.first {
            cola.removeFirst()
            guard vistos.insert(n).inserted else { continue }
            for m in salientes[n] ?? [] {
                rango[m] = max(rango[m] ?? 0, (rango[n] ?? 0) + 1)
                grado[m, default: 0] -= 1
                if grado[m] ?? 0 <= 0 { cola.append(m) }
            }
        }
        // Lo que quedo fuera por un ciclo se coloca detras de sus predecesores.
        for id in ids where !vistos.contains(id) {
            let previos = aristas.filter { $0.1 == id }.compactMap { rango[$0.0] }
            rango[id] = (previos.max() ?? 0) + 1
        }
        return rango
    }
}
