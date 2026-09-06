import CoreGraphics
import Foundation

/**
 * Ruteo de conectores por corredores libres.
 *
 * La unica pieza del pipeline que no existia en ninguna libreria. Se mantiene
 * chica a proposito.
 *
 * Por que hace falta: un motor de layout resuelve DONDE va cada nodo, pero las
 * rutas que devuelve son polilineas suaves que ignoran los obstaculos — con el
 * layout apretado, una arista de A a D atraviesa la caja C.
 *
 * Y en el v3 esto se resolvia a mano: los generadores traian corredores
 * hardcodeados como constantes magicas ("corredor derecho x~5470"). Aqui los
 * corredores se DERIVAN del layout real: las coordenadas entre cajas ya son los
 * pasillos libres, solo hay que verlos.
 *
 * Algoritmo: A* ortogonal sobre una grilla ESPARSA. Los candidatos no son
 * pixeles (seria carisimo) sino las lineas que importan: bordes de cajas con
 * holgura, centros, y los puntos medios de los huecos.
 */
struct Obstaculo {
    var id: String
    var caja: CGRect
    /// Cuanto se extiende la parte VISIBLE por debajo de la caja.
    ///
    /// El pie de una tarjeta cuelga FUERA de ella y para el ojo es parte del
    /// objeto. Sin esto la boca de abajo nace en el borde del rectangulo y la
    /// flecha atraviesa el texto — medido: cuatro aristas cruzando su propio
    /// pie en cuanto se centraron las bocas.
    var pieAlto: Double = 0
}

enum Ruteo {

    /// Cuanto se aparta una flecha de su caja antes de doblar. Es el tramo que
    /// hace que una flecha se lea como que SALE de algo, y no como una linea que
    /// pasaba por ahi.
    static let SALIDA: Double = 14

    /// El punto exacto de un lado concreto.
    static func bocaDelLado(_ o: Obstaculo, _ lado: String, holgura: Double) -> CGPoint {
        let b = o.caja
        switch lado {
        case "e": return CGPoint(x: b.maxX + holgura, y: b.midY.rounded())
        case "w": return CGPoint(x: b.minX - holgura, y: b.midY.rounded())
        case "n": return CGPoint(x: b.midX.rounded(), y: b.minY - holgura)
        // La boca de ABAJO sale por debajo del pie, no del borde del rectangulo.
        default:  return CGPoint(x: b.midX.rounded(), y: b.maxY + o.pieAlto + holgura)
        }
    }

    /**
     * Donde entra o sale una flecha de una caja.
     *
     * Con `lado`, ESE lado manda pase lo que pase. Peticion de Daniel, y no es
     * cosmetica: *"la flecha, si la conecté del lado izquierdo, por más que
     * mueva el componente al que se conectó, no se cambia de lugar"*. Sin eso,
     * un diagrama armado a mano se REORGANIZA solo cada vez que mueves una caja.
     *
     * Sin `lado` se elige el dominante, que es lo correcto para lo compilado:
     * ahi nadie eligio un lado.
     */
    static func anclaje(_ o: Obstaculo, hacia p: CGPoint, holgura: Double, lado: String? = nil) -> CGPoint {
        bocaDelLado(o, ladoElegido(o, hacia: p, lado: lado), holgura: holgura)
    }

    /**
     * EL LADO POR EL QUE SALE LA FLECHA. Se decide UNA vez y manda en todos lados.
     *
     * ⚠️ Esta funcion existe porque el router y el pegado de extremos decidian
     * el lado POR SEPARADO, con entradas distintas: el router miraba el centro
     * de la otra caja y el pegado miraba el primer punto del camino ya trazado.
     * Con las cajas en diagonal los dos daban lados DISTINTOS —el router salia
     * por el sur y el pegado re-anclaba al este— y para unir dos puntos que
     * nadie coordino, la linea tenia que volver a ENTRAR en la caja.
     *
     * Eso es lo que Daniel vio: *"flechas nunca adentro de componentes"*. No
     * era el ruteo, era que habia dos jueces para la misma pregunta.
     */
    static func ladoElegido(_ o: Obstaculo, hacia p: CGPoint, lado: String? = nil) -> String {
        if let l = lado { return l }
        let b = o.caja
        let dx = p.x - b.midX, dy = p.y - b.midY
        if abs(dx) * b.height > abs(dy) * b.width { return dx > 0 ? "e" : "w" }
        return dy > 0 ? "s" : "n"
    }

    /// El vector unitario que apunta HACIA AFUERA de una boca. En este lienzo la
    /// y crece hacia abajo, asi que el norte es negativo.
    static func normal(_ lado: String) -> CGPoint {
        switch lado {
        case "e": return CGPoint(x: 1, y: 0)
        case "w": return CGPoint(x: -1, y: 0)
        case "n": return CGPoint(x: 0, y: -1)
        default:  return CGPoint(x: 0, y: 1)
        }
    }

    /**
     * EL LADO QUE LA MANO QUISO — o `nil` si no quiso ninguno.
     *
     * ⚠️ `ladoMasCercano` SIEMPRE devuelve un lado, incluso para el centro
     * exacto de la caja, y ahi devuelve "n" por como caen los desempates.
     * Usarlo para el punto donde EMPIEZA un trazo hacia que arrancar en mitad
     * de la figura —el gesto normal— sacara la flecha por arriba y le diera la
     * vuelta a la caja entera.
     *
     * La intencion se lee en la MITAD EXTERIOR: pegado al borde derecho dijiste
     * "por la derecha"; en el centro no dijiste nada y decide el ruteo.
     */
    static func ladoIntencional(_ o: Obstaculo, _ p: CGPoint) -> String? {
        let b = o.caja
        guard b.width > 0, b.height > 0 else { return nil }
        let nx = (p.x - b.midX) / (b.width / 2)
        let ny = (p.y - b.midY) / (b.height / 2)
        guard max(abs(nx), abs(ny)) >= 0.5 else { return nil }
        if abs(nx) >= abs(ny) { return nx > 0 ? "e" : "w" }
        return ny > 0 ? "s" : "n"
    }

    /// De que lado de la caja cae un punto. Para RECORDAR por donde se conecto.
    static func ladoMasCercano(_ o: Obstaculo, _ p: CGPoint) -> String {
        let b = o.caja
        let dx = p.x - b.midX, dy = p.y - b.midY
        if abs(dx) * b.height > abs(dy) * b.width { return dx > 0 ? "e" : "w" }
        return dy > 0 ? "s" : "n"
    }

    /**
     * PEGA los extremos de una ruta a las CUATRO bocas cardinales de su caja.
     *
     * Daniel: *"asegúrate que las flechas no salgan del centro sino salgan del
     * borde, ya sea derecha izquierda arriba abajo"*. Las rutas ya tocaban el
     * borde, pero en el punto que le convenia al algoritmo — medido, un
     * conector arrancaba 54 px descentrado. El ojo espera que una flecha nazca
     * en el MEDIO de un lado, como si la caja tuviera cuatro bocas.
     *
     * El CODO se INSERTA, no se empuja al vecino: con una ruta de tres puntos
     * los dos ajustes caen sobre el MISMO punto y el segundo pisa al primero.
     */
    static func pegarALosBordes(_ ruta: [CGPoint], _ a: Obstaculo, _ b: Obstaculo,
                                ladoA: String, ladoB: String) -> [CGPoint] {
        guard ruta.count >= 2 else { return ruta }
        let inicio = bocaDelLado(a, ladoA, holgura: 0)
        let fin = bocaDelLado(b, ladoB, holgura: 0)
        /*
         * El camino que llega YA empieza y acaba en el tramo de salida: el
         * router arranca en la boca separada por la holgura, que esta sobre la
         * misma perpendicular que la boca pegada al borde. Por eso aqui no hay
         * que inventar ningun codo — basta con anteponer y posponer el punto
         * del borde, y el primer tramo sale recto hacia afuera por construccion.
         *
         * La version anterior TIRABA esos dos puntos y fabricaba una L contra el
         * primer punto del cuerpo. Cuando ese punto caia detras de la boca, la L
         * atravesaba la caja de lado a lado.
         */
        var out: [CGPoint] = [inicio]
        func empujar(_ p: CGPoint) {
            let u = out[out.count - 1]
            if abs(u.x - p.x) > 0.5 || abs(u.y - p.y) > 0.5 { out.append(p) }
        }
        for p in ruta { empujar(p) }
        empujar(fin)
        return out.count >= 2 ? colapsarColineales(out) : [inicio, fin]
    }

    /// Quita los puntos que caen en medio de un tramo recto.
    static func colapsarColineales(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in pts {
            let n = out.count
            if n >= 2 {
                let x = out[n - 2], y = out[n - 1]
                if (abs(x.x - y.x) < 0.5 && abs(y.x - p.x) < 0.5)
                    || (abs(x.y - y.y) < 0.5 && abs(y.y - p.y) < 0.5) { out[n - 1] = p; continue }
            }
            out.append(p)
        }
        return out
    }

    /*
     * ⚠️ LAS DOS CAJAS DE LOS EXTREMOS NO SON TERRENO LIBRE.
     *
     * Antes estaban EXENTAS de la colision —para que la boca, que vive a una
     * holgura del borde, no se marcara como bloqueada— y el precio era que el
     * camino podia cruzar de lado a lado su propio origen y su propio destino.
     * Es literalmente el caso que se ve peor: la flecha atraviesa las dos cajas
     * que une.
     *
     * La distincion correcta no es "exenta o no", es CUANTA holgura: las cajas
     * propias bloquean con holgura CERO (su interior, ni un pixel mas) y el
     * resto con la holgura del ruteo. Asi la boca cabe y el interior no.
     */
    private static func margen(_ o: Obstaculo, _ holgura: Double, _ propias: Set<String>) -> Double {
        propias.contains(o.id) ? 0 : holgura
    }

    /**
     * Solape ESTRICTO: ROZAR un borde no es entrar.
     *
     * ⚠️ `CGRect.contains` incluye el minimo y excluye el maximo, asi que la
     * linea de arriba de un obstaculo contaba como ocupada y la de abajo no. El
     * router solo sabia rodear por un lado, y cuando ese lado estaba cerrado
     * declaraba que no habia camino. Aqui el criterio es simetrico y el unico
     * que significa algo: se cruza cuando se INVADE, no cuando se toca.
     */
    private static func cruza(_ r: CGRect, _ caja: CGRect) -> Bool {
        r.minX < caja.maxX - 0.5 && r.maxX > caja.minX + 0.5
            && r.minY < caja.maxY - 0.5 && r.maxY > caja.minY + 0.5
    }

    private static func bloqueado(_ p: CGPoint, _ obs: [Obstaculo], _ holgura: Double, _ propias: Set<String>) -> Bool {
        let r = CGRect(origin: p, size: .zero)
        for o in obs {
            let m = margen(o, holgura, propias)
            if cruza(r, o.caja.insetBy(dx: -m, dy: -m)) { return true }
        }
        return false
    }

    private static func segmentoBloqueado(_ a: CGPoint, _ b: CGPoint, _ obs: [Obstaculo],
                                          _ holgura: Double, _ propias: Set<String>) -> Bool {
        /*
         * ⚠️ EL RECTANGULO DE UN TRAMO ORTOGONAL ES VACIO, Y `intersects`
         * DEVUELVE FALSO CON CUALQUIER RECTANGULO VACIO.
         *
         * Todos los pasos del A* son horizontales o verticales, asi que el
         * rectangulo que los envuelve mide 0 de ancho o 0 de alto. Esta prueba
         * llevaba desde el primer dia devolviendo `false` SIEMPRE: la unica
         * colision que de verdad se comprobaba era la del nodo de llegada, y una
         * arista larga podia saltar por encima de una caja sin tocar ni un nodo
         * suyo. Por eso el solape se calcula a mano en `cruza` y no con
         * `intersects`, que descarta cualquier rectangulo vacio.
         */
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                       width: abs(b.x - a.x), height: abs(b.y - a.y))
        for o in obs {
            let m = margen(o, holgura, propias)
            if cruza(r, o.caja.insetBy(dx: -m, dy: -m)) { return true }
        }
        return false
    }

    private static func unicosOrdenados(_ xs: [Double]) -> [Double] {
        Array(Set(xs.map { $0.rounded() })).sorted()
    }

    /**
     * Rutea de A a B esquivando obstaculos.
     *
     * Devuelve nil si no hay camino: el llamador decide. NUNCA devuelve una
     * ruta que atraviesa algo y finge que esta bien.
     */
    /// Cuánto se infla la zona de trabajo alrededor de las dos puntas. 240 px
    /// dan sitio para rodear una tarjeta entera por fuera sin arrastrar a la
    /// rejilla la mitad del documento.
    static let MARGEN_ZONA: Double = 240

    static func ortogonal(_ desde: Obstaculo, _ hasta: Obstaculo, _ obsTodos: [Obstaculo],
                          ladoA: String? = nil, ladoB: String? = nil,
                          holgura: Double = 14, penalizacionGiro: Double = 30,
                          maxNodos: Int = 20000) -> [CGPoint]? {
        let propias: Set<String> = [desde.id, hasta.id]
        /*
         * ⚠️ SOLO ESTORBAN LAS CAJAS QUE ESTÁN EN EL CAMINO.
         *
         * La rejilla del A* no crece con los conectores: crece con los
         * OBSTÁCULOS. Cada caja aporta tres líneas por eje —sus dos bordes y su
         * centro— y luego se insertan los puntos medios entre líneas
         * consecutivas. Con las 29 cajas del mapa de Daniel eso daba 177×177
         * casillas y ~156 mil nodos POR CONECTOR, y una flecha entre dos
         * tarjetas vecinas pagaba el precio del documento entero.
         *
         * Medido el 20 ago 2026 sobre su página: arrastrar una tarjeta con tres
         * flechas colgando costaba **1,487 ms POR FOTOGRAMA**. Eso es el "va de
         * saltos en saltos": el ratón entrega eventos cada pocos milisegundos y
         * cada uno tardaba segundo y medio.
         *
         * Una flecha solo necesita saber esquivar lo que tiene cerca. La zona es
         * la caja que une las dos puntas, inflada lo bastante para que quepa un
         * rodeo; lo de fuera no puede estorbar sin que la ruta se salga de la
         * zona, y para ese caso raro está el reintento con todo (más abajo).
         */
        let zona = desde.caja.union(hasta.caja).insetBy(dx: -MARGEN_ZONA, dy: -MARGEN_ZONA)
        let obs = obsTodos.filter { $0.caja.intersects(zona) || propias.contains($0.id) }
        let lA = ladoA ?? ladoElegido(desde, hacia: CGPoint(x: hasta.caja.midX, y: hasta.caja.midY))
        let lB = ladoB ?? ladoElegido(hasta, hacia: CGPoint(x: desde.caja.midX, y: desde.caja.midY))
        let inicio = bocaDelLado(desde, lA, holgura: holgura)
        let meta = bocaDelLado(hasta, lB, holgura: holgura)

        var xs: [Double] = [inicio.x, meta.x], ys: [Double] = [inicio.y, meta.y]
        for o in obs {
            xs.append(contentsOf: [Double(o.caja.minX) - holgura, Double(o.caja.maxX) + holgura, Double(o.caja.midX)])
            ys.append(contentsOf: [Double(o.caja.minY) - holgura, Double(o.caja.maxY) + holgura, Double(o.caja.midY)])
        }
        func conMedios(_ arr: [Double]) -> [Double] {
            var out = arr
            for i in 0..<max(0, arr.count - 1) { out.append(((arr[i] + arr[i + 1]) / 2).rounded()) }
            return unicosOrdenados(out)
        }
        let gx = conMedios(unicosOrdenados(xs)), gy = conMedios(unicosOrdenados(ys))
        guard let sx = gx.firstIndex(of: Double(inicio.x.rounded())), let sy = gy.firstIndex(of: Double(inicio.y.rounded())),
              let tx = gx.firstIndex(of: Double(meta.x.rounded())), let ty = gy.firstIndex(of: Double(meta.y.rounded()))
        else { return nil }

        func indice(_ xi: Int, _ yi: Int) -> Int { yi * gx.count + xi }
        /*
         * ⚠️ LA LLAVE MULTIPLICA POR 5, NO DESPLAZA DOS BITS.
         *
         * El referente hace `(indice << 2) | dir` con `dir` de 0 a 4 — y 4 no
         * cabe en dos bits: `| 4` se derrama al bit siguiente y produce la
         * llave del nodo SIGUIENTE. Dos casillas distintas comparten entrada en
         * `vino` y en `g`, asi que la reconstruccion salta entre caminos que no
         * se tocan.
         *
         * El sintoma no es un fallo, es una ruta FEA: se dibuja una polilinea
         * diagonal que retrocede sobre si misma, y como el conector se ve, se
         * lee como "el router es malo" en vez de "el indice esta corrupto".
         * Medido aqui el 20 ago 2026 con una prueba que exige que cada tramo
         * sea horizontal o vertical.
         *
         * Cinco direcciones (ninguna + las cuatro) necesitan base 5.
         */
        func llave(_ xi: Int, _ yi: Int, _ dir: Int) -> Int { indice(xi, yi) * 5 + dir }
        /*
         * ⚠️ TABLAS PLANAS, no diccionarios.
         *
         * `g` y `vino` eran `[Int: Double]` y `[Int: Int]`, y en el camino
         * caliente del A* cada vecino hace una consulta y una escritura: con
         * decenas de miles de nodos, el hasheo de Swift acaba pesando más que la
         * búsqueda. Como la llave ya es un entero denso —`casilla * 5 + dir`—,
         * un array del tamaño exacto indexa en un acceso y sin hashear.
         *
         * Y de paso pone un techo honesto: si la rejilla es tan grande que la
         * tabla no cabe, se devuelve `nil` y el conector cae a su escuadra de
         * respaldo en vez de congelar la app buscando. Un router que tarda
         * segundos es, para la mano, un router roto.
         */
        let casillas = gx.count * gy.count
        guard casillas * 5 <= 1_200_000 else { return nil }
        var g = [Double](repeating: .infinity, count: casillas * 5)
        var vino = [Int32](repeating: -1, count: casillas * 5)
        g[llave(sx, sy, 0)] = 0
        func h(_ xi: Int, _ yi: Int) -> Double { abs(gx[xi] - Double(meta.x)) + abs(gy[yi] - Double(meta.y)) }

        /**
         * ⚠️ AQUÍ ESTABA LA CONGELACIÓN DE TRES SEGUNDOS.
         *
         * La versión anterior guardaba la frontera en un array y hacía
         * `abierta.sort { $0.f < $1.f }` **dentro del bucle**, más un
         * `removeFirst()` que encima desplaza todo el array. Su comentario decía
         * *"para estas tallas —decenas de líneas— un array ordenado gana a un
         * heap"*, y era cierto cuando se escribió: con seis cajas la frontera
         * cabe en una mano.
         *
         * Pero la rejilla no crece con los conectores, crece con los
         * OBSTÁCULOS: cada caja aporta tres líneas por eje y después se insertan
         * los puntos medios. En el mapa de Daniel —29 cajas— eso da 177×177
         * casillas por 5 direcciones ≈ 156 mil nodos, y ordenar una frontera de
         * miles, hasta veinte mil veces, cuesta lo que costaba: **2,970 ms para
         * re-rutear los 16 conectores de una página**. Ése era el tirón que se
         * sentía al SOLTAR una tarjeta.
         *
         * Un montículo binario saca el mínimo en log n sin ordenar nada. No
         * cambia ni una ruta: cambia el orden en que se visitan los mismos
         * nodos, y el resultado de A* no depende de eso.
         */
        struct Item { var xi: Int; var yi: Int; var dir: Int; var f: Double }
        var abierta = MonticuloMin(Item(xi: sx, yi: sy, dir: 0, f: h(sx, sy))) { $0.f < $1.f }
        let DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        var explorados = 0

        while let cur = abierta.sacar() {
            explorados += 1
            if explorados > maxNodos { return nil }
            if cur.xi == tx && cur.yi == ty {
                var camino: [CGPoint] = []
                var k = llave(cur.xi, cur.yi, cur.dir)
                while true {
                    let nodo = k / 5
                    camino.append(CGPoint(x: gx[nodo % gx.count], y: gy[nodo / gx.count]))
                    let prev = vino[k]
                    if prev < 0 { break }
                    k = Int(prev)
                }
                camino.reverse()
                // Colapsar colineales.
                var simple: [CGPoint] = []
                for p in camino {
                    let n = simple.count
                    if n >= 2 {
                        let a = simple[n - 2], b = simple[n - 1]
                        if (a.x == b.x && b.x == p.x) || (a.y == b.y && b.y == p.y) {
                            simple[n - 1] = p; continue
                        }
                    }
                    if n == 0 || simple[n - 1] != p { simple.append(p) }
                }
                return [inicio] + simple + [meta]
            }

            let curK = llave(cur.xi, cur.yi, cur.dir)
            let curG = g[curK]
            for (di, d) in DIRS.enumerated() {
                let nx = cur.xi + d.0, ny = cur.yi + d.1
                guard nx >= 0, ny >= 0, nx < gx.count, ny < gy.count else { continue }
                let a = CGPoint(x: gx[cur.xi], y: gy[cur.yi])
                let b = CGPoint(x: gx[nx], y: gy[ny])
                if bloqueado(b, obs, holgura, propias) { continue }
                if segmentoBloqueado(a, b, obs, holgura, propias) { continue }
                let dir = di + 1
                let recorrido: Double = abs(b.x - a.x) + abs(b.y - a.y)
                let giro: Double = (cur.dir != 0 && cur.dir != dir) ? penalizacionGiro : 0
                let costo: Double = recorrido + giro
                let nk = llave(nx, ny, dir)
                let tentativo = curG + costo
                if tentativo < g[nk] {
                    g[nk] = tentativo
                    vino[nk] = Int32(curK)
                    abierta.meter(Item(xi: nx, yi: ny, dir: dir, f: tentativo + h(nx, ny)))
                }
            }
        }
        return nil
    }
}

/**
 * Conectores. LA REGLA: un conector guarda A QUIEN une, jamas por donde pasa.
 *
 * Guardar la ruta y no recalcularla es lo que produce flechas flotando en el
 * aire despues de mover una tarjeta — el sintoma clasico de un diagrama que se
 * degrada con el uso. El conector es una RELACION; su dibujo es consecuencia.
 */
enum Conectores {

    static func obstaculoDe(_ e: Elemento) -> Obstaculo {
        // El pie cuelga por DEBAJO: se declara para que la boca sur nazca por
        // fuera de el, no atravesandolo.
        let pie = max(0, e.cajaVisual.maxY - e.caja.maxY)
        return Obstaculo(id: e.id, caja: e.caja, pieAlto: pie)
    }

    /// Recalcula la ruta de un conector contra el estado actual.
    ///
    /// Si no hay corredor cae a la recta entre puertos en vez de devolver nada:
    /// un conector sin ruta DESAPARECE, y desaparecer es peor que verse
    /// cruzando algo — al menos la linea fea dice que la relacion existe.
    /**
     * MIENTRAS LA MANO ARRASTRA NO SE BUSCA CAMINO.
     *
     * Medido el 20 ago 2026 en la página de Daniel: arrastrar una tarjeta con
     * tres flechas costaba **1,487 ms por fotograma** — el ratón entrega eventos
     * cada pocos milisegundos y cada uno lanzaba tres búsquedas A* (y hasta
     * NUEVE, porque el ruteo reintenta con tres holguras distintas). Eso es
     * exactamente lo que se sentía: *"va de saltos en saltos"*.
     *
     * Y buscar el camino óptimo mientras la caja está EN EL AIRE no sirve para
     * nada: la posición cambia en el siguiente milisegundo, así que se calcula
     * un óptimo para un sitio en el que la tarjeta no se va a quedar. Peor aún,
     * las rutas dan saltos raros a mitad del gesto.
     *
     * En modo rápido la flecha usa la misma escuadra de respaldo que ya existía
     * —sale por la perpendicular de cada boca y cruza— que es una L limpia y
     * cuesta microsegundos. Al SOLTAR se rutea de verdad. Es lo que hace
     * cualquier editor de diagramas, y no es una concesión: la ruta buena se
     * calcula cuando ya se sabe dónde quedó la caja.
     */
    static func rutear(_ conn: Elemento, _ elementos: [Elemento], rapido: Bool = false) -> Elemento {
        var c = conn
        guard let desde = elementos.first(where: { $0.id == conn.desdeId }),
              let hasta = elementos.first(where: { $0.id == conn.hastaId })
        else { c.ponerRuta([]); return c }

        let a = obstaculoDe(desde), b = obstaculoDe(hasta)
        /*
         * LOS DOS LADOS SE DECIDEN AQUI Y NADIE MAS LOS VUELVE A DECIDIR.
         *
         * El que la mano fijo (`fromPort`/`toPort`) manda; si no hay, el
         * dominante hacia la otra caja. Se pasan tal cual al router, al pegado
         * de extremos y a las variantes recta y curva, para que las cuatro
         * rutas nazcan de la MISMA boca.
         */
        let ladoA = Ruteo.ladoElegido(a, hacia: CGPoint(x: b.caja.midX, y: b.caja.midY),
                                      lado: conn.crudo["fromPort"]?.s)
        let ladoB = Ruteo.ladoElegido(b, hacia: CGPoint(x: a.caja.midX, y: a.caja.midY),
                                      lado: conn.crudo["toPort"]?.s)

        // Los conectores, la tinta y las secciones no son obstaculos: rodearlos
        // no aporta y encarece el ruteo sin mejorar el dibujo.
        let obs = elementos
            .filter { $0.tipo != "connector" && $0.tipo != "ink" && $0.tipo != "frame" }
            .map(obstaculoDe)

        // CODOS A MANO: si la mano decidio por donde pasa, el router no
        // reescribe su decision. Solo re-pega los extremos.
        if let w = conn.crudo["waypoints"]?.arr, !w.isEmpty {
            let codos = w.map { CGPoint(x: $0["x"]?.num ?? 0, y: $0["y"]?.num ?? 0) }
            let d = Ruteo.bocaDelLado(a, ladoA, holgura: 0)
            let h = Ruteo.bocaDelLado(b, ladoB, holgura: 0)
            // Con SALIDA: el tramo perpendicular que aparta la linea de la caja
            // antes del primer codo. Sin el, un codo puesto detras de la boca
            // hacia que la flecha entrara a su propia caja para alcanzarlo.
            let sa = Ruteo.bocaDelLado(a, ladoA, holgura: Ruteo.SALIDA)
            let sb = Ruteo.bocaDelLado(b, ladoB, holgura: Ruteo.SALIDA)
            let cruda = [d, sa] + codos + [sb, h]
            /*
             * Un CODO en ruta ortogonal produce ÁNGULOS RECTOS.
             *
             * El referente devuelve la polilínea cruda: unir los codos en línea
             * directa da diagonales, y una diagonal en una ruta que se llama "de
             * codos" se lee como que el conector se rompió. sfmap es el primer
             * productor de `waypoints` en las dos superficies —el campo existía y
             * nada lo escribía nunca— así que aquí se define qué es un codo bien
             * hecho: el punto por el que la mano dijo que pase, y esquinas.
             */
            // El eje de salida sale del lado de la boca: sin él el primer tramo
            // gira nada más nacer y la flecha arranca de costado.
            let eje = (ladoA == "n" || ladoA == "s") ? "v" : "h"
            c.ponerRuta(conn.ruteo == "ortogonal" ? enAngulosRectos(cruda, ejeInicial: eje) : cruda)
            return c
        }

        // RECTA y CURVA no necesitan router: van de puerto a puerto. La curva se
        // dibuja curva en el pintor; su ruta siguen siendo los dos extremos,
        // porque guardar los puntos de una bezier obligaria al hit-test a
        // reconstruirla y ahi es donde nacen las divergencias.
        let ruteo = conn.ruteo
        if ruteo == "recta" || ruteo == "curva" {
            c.ponerRuta([Ruteo.bocaDelLado(a, ladoA, holgura: 0), Ruteo.bocaDelLado(b, ladoB, holgura: 0)])
            return c
        }

        for holgura in [14.0, 8.0, 4.0] where !rapido {
            if let ruta = Ruteo.ortogonal(a, b, obs, ladoA: ladoA, ladoB: ladoB, holgura: holgura) {
                c.ponerRuta(Ruteo.pegarALosBordes(ruta, a, b, ladoA: ladoA, ladoB: ladoB))
                return c
            }
        }
        // Sin corredor: recta de boca a boca, pero SALIENDO por la perpendicular
        // de cada lado. Una linea fea que rodea se lee como "no cabia"; una que
        // nace dentro de la caja se lee como que el conector esta roto.
        c.ponerRuta(Ruteo.colapsarColineales(Conectores.enAngulosRectos(
            [Ruteo.bocaDelLado(a, ladoA, holgura: 0), Ruteo.bocaDelLado(a, ladoA, holgura: Ruteo.SALIDA),
             Ruteo.bocaDelLado(b, ladoB, holgura: Ruteo.SALIDA), Ruteo.bocaDelLado(b, ladoB, holgura: 0)],
            ejeInicial: (ladoA == "n" || ladoA == "s") ? "v" : "h")))
        return c
    }

    /**
     * Convierte una polilínea en ortogonal PASANDO por cada codo.
     *
     * ⚠️ Un codo define un CORREDOR, no una esquina. La primera versión unía
     * cada par con una L, y con dos bocas horizontales y un codo abajo el
     * resultado bajaba y volvía a subir POR LA MISMA VERTICAL: ortogonal, sí, y
     * doblado sobre sí mismo — se lee peor que la diagonal que venía a arreglar.
     *
     * La regla correcta es una Z por tramo: se avanza la mitad sobre el eje de
     * viaje, se cruza al carril del codo, y se sigue. Con un codo debajo de dos
     * cajas enfrentadas eso da una U limpia que pasa exactamente por donde la
     * mano dijo.
     *
     * `ejeInicial` es el eje por el que SALE la flecha: una boca este/oeste sale
     * en horizontal y una norte/sur en vertical. Sin ese dato, el primer tramo
     * gira nada más nacer y el conector arranca de lado.
     */
    static func enAngulosRectos(_ pts: [CGPoint], ejeInicial: String = "h") -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        let horizontal = ejeInicial == "h"
        var out: [CGPoint] = [pts[0]]
        for i in 1..<pts.count {
            let p = out[out.count - 1], q = pts[i]
            let mismaFila = abs(p.y - q.y) < 0.5, mismaCol = abs(p.x - q.x) < 0.5
            if mismaFila || mismaCol { out.append(q); continue }
            if horizontal {
                let mx = ((p.x + q.x) / 2).rounded()
                out.append(CGPoint(x: mx, y: p.y))
                out.append(CGPoint(x: mx, y: q.y))
            } else {
                let my = ((p.y + q.y) / 2).rounded()
                out.append(CGPoint(x: p.x, y: my))
                out.append(CGPoint(x: q.x, y: my))
            }
            out.append(q)
        }
        // Colapsa los puntos colineales que la Z pueda dejar pegados.
        var limpio: [CGPoint] = []
        for p in out {
            let n = limpio.count
            if n >= 2 {
                let a = limpio[n - 2], b = limpio[n - 1]
                if (abs(a.x - b.x) < 0.5 && abs(b.x - p.x) < 0.5)
                    || (abs(a.y - b.y) < 0.5 && abs(b.y - p.y) < 0.5) { limpio[n - 1] = p; continue }
            }
            if n == 0 || hypot(limpio[n - 1].x - p.x, limpio[n - 1].y - p.y) > 0.5 { limpio.append(p) }
        }
        return limpio
    }

    /// Re-rutea SOLO los conectores tocados por lo que se movio.
    ///
    /// Recalcular todos en cada frame es caro y no hace falta. La excepcion —una
    /// tarjeta movida puede estorbar a una flecha ajena— se corrige al SOLTAR:
    /// re-rutear todo mientras se arrastra hace que las flechas lejanas salten
    /// sin motivo aparente.
    static func rerutear(_ elementos: [Elemento], movidos: Set<String>, rapido: Bool = false) -> [Elemento] {
        elementos.map { e in
            guard e.tipo == "connector" else { return e }
            guard movidos.contains(e.desdeId ?? "") || movidos.contains(e.hastaId ?? "") else { return e }
            return rutear(e, elementos, rapido: rapido)
        }
    }

    /// Re-rutea TODO. Se usa al soltar, cuando ya se sabe la posicion final.
    static func reruteaTodo(_ elementos: [Elemento]) -> [Elemento] {
        elementos.map { $0.tipo == "connector" ? rutear($0, elementos) : $0 }
    }

    /// Conectores que apuntan a algo que ya no existe. Se van con su extremo.
    static func huerfanos(_ elementos: [Elemento]) -> Set<String> {
        let ids = Set(elementos.map(\.id))
        return Set(elementos.filter {
            $0.tipo == "connector" && (!ids.contains($0.desdeId ?? "") || !ids.contains($0.hastaId ?? ""))
        }.map(\.id))
    }
}


/**
 * UN MONTÍCULO BINARIO MÍNIMO, lo justo para la frontera del A*.
 *
 * No se trae una dependencia por 40 líneas, y tenerlo aquí lo hace auditable:
 * la propiedad que importa —`sacar()` devuelve siempre el de menor `f`— se
 * prueba directamente en `RutaTests`.
 *
 * Es genérico sobre el elemento y recibe la comparación, así que no obliga al
 * `Item` del router a conformar `Comparable` ni a nombrar su campo de coste.
 */
struct MonticuloMin<T> {
    private var v: [T]
    private let menor: (T, T) -> Bool

    init(_ primero: T, _ menor: @escaping (T, T) -> Bool) {
        v = [primero]; self.menor = menor
    }

    var vacio: Bool { v.isEmpty }
    var cuenta: Int { v.count }

    mutating func meter(_ x: T) {
        v.append(x)
        var i = v.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            guard menor(v[i], v[p]) else { break }
            v.swapAt(i, p); i = p
        }
    }

    mutating func sacar() -> T? {
        guard !v.isEmpty else { return nil }
        let cima = v[0]
        let ultimo = v.removeLast()
        guard !v.isEmpty else { return cima }
        v[0] = ultimo
        var i = 0
        while true {
            let iz = 2 * i + 1, de = 2 * i + 2
            var m = i
            if iz < v.count, menor(v[iz], v[m]) { m = iz }
            if de < v.count, menor(v[de], v[m]) { m = de }
            if m == i { break }
            v.swapAt(i, m); i = m
        }
        return cima
    }
}
