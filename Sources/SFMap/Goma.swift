import CoreGraphics
import Foundation

/**
 * LA GOMA — qué alcanza el disco y qué se lleva.
 *
 * Aquí vive la regla, PURA y sin pantalla, porque el fallo que esto corrige era
 * exactamente una mentira entre la pantalla y la regla: la goma pintaba un
 * disco de un tamaño y borraba por un PUNTO. Un instrumento que promete un
 * área y actúa en otra no se puede usar con confianza — la mano aprende a
 * apuntar en vez de a pasar, que es justo lo que una goma no debe pedir.
 *
 * Tres decisiones, y las tres se pueden defender:
 *
 * 1. **El disco es la verdad.** El radio que se pinta es el radio que borra, al
 *    zoom que sea. Por eso el radio de MUNDO se calcula desde el de PANTALLA
 *    (`radioMundo`) y no al revés: alejarte no puede convertir la goma en una
 *    aguja invisible.
 *
 * 2. **Alcance, no fuerza.** `tinta` solo se lleva trazos; `todo` se lleva
 *    también cajas, texto, flechas y secciones. Poder anotar encima de un
 *    diagrama y limpiar la anotación SIN arriesgar el diagrama es lo que hace
 *    que la goma se use sin miedo; y cuando de verdad quieres tirar un
 *    componente, cambias el alcance a propósito.
 *
 * 3. **La sección se borra por su MARCO.** Un `frame` ocupa media pantalla:
 *    si contara su interior, pasar la goma por encima de lo que hay DENTRO se
 *    llevaría el contenedor entero al primer roce. Se agarra por donde se
 *    agarra a ojo — su borde.
 */
struct Goma {

    /// Qué tipos de elemento entran en el disco.
    enum Alcance: String, CaseIterable {
        /// Solo trazos de tinta. El diagrama de debajo no corre peligro.
        case tinta
        /// Todo lo que toque: tinta, cajas, texto, flechas y secciones.
        case todo

        var nombre: String { self == .tinta ? "Tinta" : "Todo" }
        var ayuda: String {
            self == .tinta ? "Solo se lleva trazos" : "Se lleva lo que toque"
        }
    }

    /// Diámetro en unidades de MUNDO, como el grosor de la tinta.
    var grosor: Double = 24
    var alcance: Alcance = .tinta

    /// Los cinco tamaños del panel. Empiezan más gruesos que los del lápiz
    /// porque una goma fina no es una goma: es un lápiz que quita.
    static let grosores: [Double] = [8, 16, 28, 48, 80]

    /// El disco NUNCA baja de esto en pantalla. Al 10% de zoom un grosor de 24
    /// serían 2.4 px: un punto que ni se ve ni se apunta.
    static let MINIMO_PANTALLA = 11.0
    /// Ni sube de esto. Los topes se aplican EN PANTALLA y a la cuenta que usan
    /// los dos —el pintado y el borrado—, así que el disco sigue diciendo la
    /// verdad: acotar solo lo que se dibuja es exactamente el fallo que esto
    /// corrige, con el signo cambiado.
    static let MAXIMO_PANTALLA = 260.0

    /// El radio en unidades de MUNDO que de verdad borra, para una cámara dada.
    /// El de pantalla manda, y por eso esta cuenta vive en un solo sitio: si el
    /// pintado y el borrado la hicieran cada uno por su lado, volverían a
    /// divergir en cuanto alguien tocara uno de los dos.
    func radioMundo(zoom: Double) -> Double {
        let z = max(0.0001, zoom)
        let enPantalla = min(max(grosor / 2 * z, Goma.MINIMO_PANTALLA / 2), Goma.MAXIMO_PANTALLA / 2)
        return enPantalla / z
    }

    /// Y el mismo radio en píxeles de pantalla, que es lo que se pinta.
    func radioPantalla(zoom: Double) -> Double {
        radioMundo(zoom: zoom) * max(0.0001, zoom)
    }

    /// Sube o baja al siguiente tamaño de la lista. Es lo que mueve el dial de
    /// la tableta: pasos con TOPE, no una rampa infinita que se pasa de largo.
    static func grosorAjustado(_ actual: Double, pasos: Int) -> Double {
        guard pasos != 0 else { return actual }
        // El más cercano de la lista es el punto de partida: si el valor viene
        // de otro sitio (un documento viejo, un ajuste a mano) el dial tiene
        // que seguir moviéndose, no quedarse clavado por no encontrarse.
        let i = grosores.enumerated()
            .min { abs($0.element - actual) < abs($1.element - actual) }?.offset ?? 0
        return grosores[max(0, min(grosores.count - 1, i + pasos))]
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la regla
    // ════════════════════════════════════════════════════════════════════════

    /**
     * ¿El disco alcanza este elemento?
     *
     * `centro` y `radio` van en unidades de MUNDO. Devuelve `false` para lo
     * bloqueado siempre: el candado manda sobre mover, borrar y acomodar, y una
     * goma que se salta el candado lo convierte en decoración.
     */
    static func alcanza(_ e: Elemento, centro: CGPoint, radio: Double, alcance: Alcance) -> Bool {
        guard !e.bloqueado else { return false }
        if alcance == .tinta && e.tipo != "ink" { return false }

        // El giro se deshace en el PUNTO, no en la figura: es la misma
        // inversión que hace el hit-test del puntero, y hacerla en un solo
        // sentido es lo que evita que algo se vea en un sitio y se agarre en otro.
        let p = Geo.aLocal(e, centro)

        switch e.tipo {
        case "ink":
            let pts = e.trazoPuntos
            guard pts.count > 1 else {
                // Un toque de pluma es un punto suelto, y también se borra.
                guard let q = pts.first else { return false }
                return hypot(p.x - (e.x + q.x), p.y - (e.y + q.y)) <= radio + medioTrazo(e)
            }
            let alcance = radio + medioTrazo(e)
            let ox = e.x, oy = e.y
            for i in 0..<(pts.count - 1) {
                let a = CGPoint(x: ox + pts[i].x, y: oy + pts[i].y)
                let b = CGPoint(x: ox + pts[i + 1].x, y: oy + pts[i + 1].y)
                if Geo.distanciaASegmento(p, a, b) <= alcance { return true }
            }
            return false

        case "connector":
            let r = e.ruta
            guard r.count > 1 else { return false }
            for i in 0..<(r.count - 1) where Geo.distanciaASegmento(p, r[i], r[i + 1]) <= radio {
                return true
            }
            return false

        case "frame":
            // Por el MARCO. Dentro no cuenta: ver arriba, decisión 3.
            return distanciaAlBorde(e.caja, p) <= radio

        default:
            return distanciaACaja(e.caja, p) <= radio
        }
    }

    /// Lo que la tinta se ENSANCHA por encima de su grosor nominal cuando la
    /// presión aprieta. Es el mismo número que usa el agarre del puntero: si la
    /// goma alcanzara menos que el ojo, pasarías por encima de tinta visible sin
    /// llevártela.
    private static func medioTrazo(_ e: Elemento) -> Double {
        Tinta.diametro(Tinta.Opciones(grosor: e.grosorTinta, marcador: e.esMarcador))
            * 0.5 * Tinta.ANCHO_MAX
    }

    /// Distancia de un punto a un rectángulo RELLENO: 0 si está dentro.
    static func distanciaACaja(_ r: CGRect, _ p: CGPoint) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    /// Distancia de un punto al BORDE de un rectángulo: dentro también cuenta,
    /// midiendo lo que le falta para salir.
    static func distanciaAlBorde(_ r: CGRect, _ p: CGPoint) -> Double {
        guard r.contains(p) else { return distanciaACaja(r, p) }
        return min(min(p.x - r.minX, r.maxX - p.x), min(p.y - r.minY, r.maxY - p.y))
    }

    /// Los ids que el disco alcanza, en una pasada. Lo usa el gesto para ir
    /// MARCANDO mientras la mano se mueve, y confirmar de una sola vez al soltar.
    static func alcanzados(_ elementos: [Elemento], centro: CGPoint, radio: Double,
                           alcance: Alcance) -> [String] {
        elementos.filter { alcanza($0, centro: centro, radio: radio, alcance: alcance) }
                 .map(\.id)
    }
}
