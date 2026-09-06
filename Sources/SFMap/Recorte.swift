import Foundation
import CoreGraphics

/**
 * RECORTAR UNA IMAGEN — la tijera que faltaba (26 ago 2026).
 *
 * Daniel: *"no hay para cortar componente. Yo pudiera darle clic derecho a
 * alguna sección que me diga cortar, o poder arrastrar, ver sombreado lo que
 * voy a cortar, y darle enter, y ahí cortar a mi preferencia."*
 *
 * Hasta hoy la única forma de quitarle el borde a una captura era salir a un
 * editor, recortar el archivo y volver a pegarlo — perdiendo de paso el sitio
 * y el tamaño que ya le habías dado.
 *
 * DOS DECISIONES QUE SOSTIENEN ESTO:
 *
 * 1. **NO SE TOCA EL ARCHIVO.** El recorte es una fracción `crop` (0..1 sobre
 *    la imagen ORIGINAL) guardada en el elemento. Es reversible para siempre,
 *    viaja con el documento y no duplica bytes. Recortar destruyendo el píxel
 *    es la clase de gesto que no se puede deshacer al día siguiente.
 * 2. **LA ARITMÉTICA VIVE AQUÍ, PURA.** Recortar lo ya recortado compone
 *    fracciones sobre fracciones, y ese es exactamente el sitio donde se cuela
 *    un error que nadie nota hasta el tercer recorte. Se prueba sin abrir una
 *    ventana.
 */
enum Recorte {

    /// Qué parte del ORIGINAL se ve, en fracciones 0..1. Entera si no hay recorte.
    static func de(_ e: Elemento) -> CGRect {
        guard let c = e.crudo["crop"]?.obj,
              let w = c["w"]?.num, let h = c["h"]?.num, w > 0, h > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(x: c["x"]?.num ?? 0, y: c["y"]?.num ?? 0, width: w, height: h)
    }

    static func tieneRecorte(_ e: Elemento) -> Bool {
        de(e) != CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// La selección, ya limpia: metida dentro de la caja y con un mínimo que
    /// impide dejar una imagen de dos píxeles por un clic mal soltado.
    static func encajar(_ seleccion: CGRect, en caja: CGRect) -> CGRect? {
        let r = seleccion.intersection(caja)
        guard !r.isNull, r.width >= 12, r.height >= 12 else { return nil }
        return r
    }

    /**
     * Aplicar una selección hecha en coordenadas del MUNDO.
     *
     * Devuelve el nuevo `crop` (sobre el original) y la nueva caja. La caja
     * nueva ES la selección: lo que queda se queda DONDE ESTABA, sin saltar ni
     * re-encuadrarse. Un recorte que además mueve la imagen obliga a recolocar
     * lo que ya estaba colocado, y entonces recortar cuesta dos gestos.
     */
    static func aplicar(_ e: Elemento, seleccion: CGRect) -> (crop: CGRect, caja: CGRect)? {
        let caja = e.caja
        guard caja.width > 0, caja.height > 0, let r = encajar(seleccion, en: caja) else { return nil }
        let c = de(e)
        // Fracción DENTRO de lo que hoy se ve…
        let fx = (r.minX - caja.minX) / caja.width
        let fy = (r.minY - caja.minY) / caja.height
        let fw = r.width / caja.width
        let fh = r.height / caja.height
        // …compuesta sobre la fracción que ya estaba recortada del original.
        let nuevo = CGRect(x: c.minX + fx * c.width, y: c.minY + fy * c.height,
                           width: fw * c.width, height: fh * c.height)
        return (nuevo, r)
    }

    /// El rectángulo de PÍXELES a pedirle a la imagen original.
    /// La Y de una `CGImage` cuenta desde arriba, igual que este `crop`.
    static func enPixeles(_ crop: CGRect, ancho: Int, alto: Int) -> CGRect {
        CGRect(x: (crop.minX * Double(ancho)).rounded(),
               y: (crop.minY * Double(alto)).rounded(),
               width: max(1, (crop.width * Double(ancho)).rounded()),
               height: max(1, (crop.height * Double(alto)).rounded()))
            .intersection(CGRect(x: 0, y: 0, width: ancho, height: alto))
    }

    /// El parche que se escribe en el elemento al confirmar.
    static func parche(crop: CGRect, caja: CGRect) -> [String: Json?] {
        ["crop": .objeto(["x": .numero(crop.minX), "y": .numero(crop.minY),
                          "w": .numero(crop.width), "h": .numero(crop.height)]),
         "x": .numero(caja.minX), "y": .numero(caja.minY),
         "width": .numero(caja.width), "height": .numero(caja.height)]
    }

    /// Deshacer el recorte sin deshacer el resto del trabajo: la imagen vuelve
    /// a estar entera CONSERVANDO la esquina y creciendo hacia fuera.
    static func quitar(_ e: Elemento) -> [String: Json?] {
        let c = de(e)
        guard c.width > 0, c.height > 0 else { return ["crop": nil] }
        return ["crop": nil,
                "width": .numero(e.ancho / c.width), "height": .numero(e.alto / c.height)]
    }

    // ── el estado del gesto ────────────────────────────────────────────────
    //
    // Vive aparte del lienzo para que la máquina de estados —entrar, arrastrar,
    // confirmar, cancelar— se pueda probar entera sin ratón.
    struct Sesion {
        let id: String
        /// La caja del elemento al entrar: el recorte nunca sale de aquí.
        let limite: CGRect
        /// Lo que se va a conservar. Empieza siendo TODO: así, si Daniel pulsa
        /// Enter sin arrastrar, no pasa nada — en vez de borrarle la imagen.
        var seleccion: CGRect
        var arrastrando = false

        init(id: String, caja: CGRect) {
            self.id = id; self.limite = caja; self.seleccion = caja
        }

        mutating func empezar(_ p: CGPoint) {
            arrastrando = true
            seleccion = CGRect(origin: p, size: .zero)
            ancla = p
        }
        mutating func mover(_ p: CGPoint) {
            guard arrastrando, let a = ancla else { return }
            seleccion = CGRect(x: min(a.x, p.x), y: min(a.y, p.y),
                               width: abs(p.x - a.x), height: abs(p.y - a.y))
                .intersection(limite)
        }
        mutating func soltar() {
            arrastrando = false
            // Un clic seco (sin arrastre real) NO recorta: vuelve a ser todo.
            if seleccion.width < 12 || seleccion.height < 12 { seleccion = limite }
        }
        /// ¿Hay algo que confirmar, o la selección es la imagen entera?
        var recorta: Bool {
            abs(seleccion.width - limite.width) > 1 || abs(seleccion.height - limite.height) > 1
        }
        private var ancla: CGPoint?
    }
}
