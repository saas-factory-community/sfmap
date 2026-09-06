import Foundation

/**
 * EL ORDEN DE APILADO: cuatro movimientos y una sola regla.
 *
 * Todo esto es una funcion PURA sobre una lista de ids ordenada de fondo a
 * frente. No toca elementos, no toca el documento y no sabe que existe una
 * pantalla: entra un orden y sale otro. Vive aparte porque las trampas del
 * apilado no estan en pintar, estan en la aritmetica — y esa se puede probar
 * sin abrir una ventana.
 */
enum Orden {

    enum Movimiento {
        case alFrente, adelante, atras, alFondo

        var nombre: String {
            switch self {
            case .alFrente: "traer al frente"
            case .adelante: "una capa adelante"
            case .atras:    "una capa atras"
            case .alFondo:  "enviar al fondo"
            }
        }
    }

    /**
     * El orden nuevo, o `nil` si no habria cambio.
     *
     * ⚠️ Devolver `nil` en vez del mismo orden NO es un detalle. Sin eso, pulsar
     * "adelante" sobre algo que ya esta arriba del todo apila un paso de
     * deshacer que no deshace nada: tres pulsaciones de mas y ⌘Z deja de
     * responder durante tres pulsaciones. Un gesto que no cambia nada no puede
     * gastar historia.
     *
     * LAS DOS REGLAS que hacen que esto se sienta bien:
     *
     * 1. LO SELECCIONADO CONSERVA SU ORDEN RELATIVO. Si mandas tres cosas al
     *    frente, siguen apiladas entre si como estaban. Reordenarlas de paso
     *    —aunque sea "solo" al orden del array— destruye trabajo que el ojo ya
     *    habia hecho, y ademas nadie lo pidio.
     *
     * 2. UN PASO SALTA AL VECINO NO SELECCIONADO. Moviendo dos cosas que estan
     *    pegadas, la de abajo no debe "adelantar" a la de arriba: se moverian
     *    una contra otra en vez de moverse JUNTAS, y a la tercera pulsacion el
     *    grupo estaria del reves. Se salta sobre quien NO va contigo.
     */
    static func reordenar(_ ids: [String], seleccion: Set<String>,
                          _ mov: Movimiento) -> [String]? {
        let sel = ids.filter { seleccion.contains($0) }
        guard !sel.isEmpty, sel.count < ids.count else { return nil }

        var out = ids
        switch mov {
        case .alFrente:
            out = ids.filter { !seleccion.contains($0) } + sel
        case .alFondo:
            out = sel + ids.filter { !seleccion.contains($0) }

        case .adelante:
            // De arriba hacia abajo: el de mas arriba se coloca primero, y los
            // de debajo ya se encuentran con el sitio ocupado por un compañero.
            // Al reves, el primero en moverse arrastraria a los demas dos pasos.
            var i = out.count - 2
            while i >= 0 {
                if seleccion.contains(out[i]), !seleccion.contains(out[i + 1]) {
                    out.swapAt(i, i + 1)
                }
                i -= 1
            }
        case .atras:
            var i = 1
            while i < out.count {
                if seleccion.contains(out[i]), !seleccion.contains(out[i - 1]) {
                    out.swapAt(i, i - 1)
                }
                i += 1
            }
        }
        return out == ids ? nil : out
    }

    /**
     * JUNTAR EN EL APILADO lo que se acaba de agrupar.
     *
     * ⚠️ Sin esto, un grupo puede tener un EXTRAÑO en medio: agrupas dos cajas
     * que estaban en z 1 y 5 y lo que hay en z 3 se queda entre ellas para
     * siempre. Se mueven juntas —`reordenar` respeta la seleccion— pero el
     * intruso viaja con ellas como un pasajero, y al pintar aparece partiendo
     * el grupo por la mitad. Nadie entiende por que.
     *
     * Se suben al sitio del MIEMBRO MAS ALTO y no al frente de todo: agrupar
     * es una operacion sobre la estructura, no sobre la profundidad. Traer el
     * grupo al frente sin que lo hayas pedido te mueve trabajo que ya estaba
     * colocado — y ahi si perderias algo.
     */
    static func juntar(_ ids: [String], grupo: Set<String>) -> [String]? {
        let miembros = ids.filter { grupo.contains($0) }
        guard miembros.count >= 2 else { return nil }
        let resto = ids.filter { !grupo.contains($0) }
        guard let masAlto = ids.lastIndex(where: { grupo.contains($0) }) else { return nil }
        // Cuantos NO miembros quedan por debajo del mas alto: ahi es donde se
        // inserta el bloque para que el mas alto conserve su altura.
        let corte = ids[..<masAlto].filter { !grupo.contains($0) }.count
        let out = Array(resto[..<corte]) + miembros + Array(resto[corte...])
        return out == ids ? nil : out
    }
}
