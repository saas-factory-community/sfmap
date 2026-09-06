import AppKit
import CoreGraphics

/**
 * EL LAZO — el cuarto mecanismo: el que enseña que un grafo es TOPOLOGÍA y un
 * lazo es DINÁMICA.
 *
 * Daniel, 28 ago 2026, con el enactivo HTML `grafo-vs-lazo.html` delante:
 * *"a ver, haz lo mismo en sfmap, el enactivo me refiero"*.
 *
 * Los nodos y las flechas están quietos: son el mapa. Al pulsar CORRER un pulso
 * recorre ENTRADA → HACER → MEDIR → COMPARAR y, si el error no es cero y existe
 * la flecha de regreso, vuelve a HACER; cada vuelta sube el resultado hasta que
 * el sensor dice que quedó. Tres controles, cada uno una ley:
 *   · CORRER          — los nodos no cambian; lo que cambia es lo que corre por ellos.
 *   · regreso SÍ/NO   — sin ciclo no hay corrección: un DAG entrega sin llegar.
 *   · el dial         — la REFERENCIA es un techo: bajarla "termina" antes con menos.
 *
 * Misma doctrina que los otros tres: nada de esto se guarda en `draw` (vive en
 * `Mecanismo.Estado`), el pintado es determinista para un estado dado, y el
 * reloj de 60 fps SE MUERE cuando el pulso llega a ENTREGAR.
 */
enum Lazo {

    /// Cuánto sube el resultado por vuelta.
    static let paso = 0.17
    /// Duración de cada tramo, en segundos: entrada→hacer · hacer→medir ·
    /// medir→comparar · comparar→hacer (regreso) · comparar→entregar.
    static let duracion: [Double] = [0.50, 0.50, 0.50, 0.90, 0.50]
    static let nombres = ["ENTRADA", "HACER", "MEDIR", "COMPARAR", "ENTREGAR"]
    static let subtitulos = ["la tarea", "actuador", "sensor", "¿qué tan lejos?", "el mundo"]

    /// El estado VIVO de un lazo. En memoria, por elemento.
    final class Vivo {
        var referencia = 0.78
        var resultado = 0.12
        var vueltas = 0
        /// -1 = quieto (mapa) · 0…4 = tramo que recorre el pulso.
        var seg = -1
        var t = 0.0
        var corriendo = false
        var terminado = false
        var regreso = true
        var veredicto = ""
        /// El nodo encendido (el último que tocó el pulso).
        var caliente = -1
        init(referencia: Double = 0.78) { self.referencia = referencia }
    }

    static func error(_ v: Vivo) -> Double { max(0, v.referencia - v.resultado) }

    static func arrancar(_ v: Vivo) {
        v.resultado = 0.12; v.vueltas = 0; v.seg = 0; v.t = 0
        v.corriendo = true; v.terminado = false; v.veredicto = ""; v.caliente = 0
    }

    static func reiniciar(_ v: Vivo) {
        v.resultado = 0.12; v.vueltas = 0; v.seg = -1; v.t = 0
        v.corriendo = false; v.terminado = false; v.veredicto = ""; v.caliente = -1
    }

    /// UN paso de reloj. Función pura del estado y de `dt`: por eso se puede
    /// probar sin Timer y por eso dos corridas iguales dan lo mismo.
    static func avanzar(_ v: Vivo, dt: Double) {
        guard v.corriendo, v.seg >= 0, v.seg < duracion.count else { return }
        v.t += dt / duracion[v.seg]
        guard v.t >= 1 else { return }
        v.t = 0
        switch v.seg {
        case 0, 3:                       // llegó a HACER (de entrada o por regreso)
            v.resultado = min(1, v.resultado + paso); v.vueltas += 1
            v.seg = 1; v.caliente = 1
        case 1:                          // llegó a MEDIR
            v.seg = 2; v.caliente = 2
        case 2:                          // llegó a COMPARAR: la decisión
            v.caliente = 3
            v.seg = (error(v) > 0.005 && v.regreso) ? 3 : 4
        default:                         // llegó a ENTREGAR
            v.caliente = 4
            v.corriendo = false; v.terminado = true
            v.veredicto = error(v) > 0.005 ? "ENTREGÓ SIN LLEGAR" : "LLEGÓ"
        }
    }

    // ── GEOMETRÍA ───────────────────────────────────────────────────────────

    /// La zona del grafo: el 64 % izquierdo, encima de los botones y el dial.
    static func zonaGrafo(_ e: Elemento) -> CGRect {
        CGRect(x: e.x + 24, y: e.y + 22, width: e.ancho * 0.64 - 24,
               height: e.alto - 22 - 26 - 22 - 26 - 44 * k(e))
    }

    /// El riel del comparador: el 30 % derecho.
    static func zonaRiel(_ e: Elemento) -> CGRect {
        let g = zonaGrafo(e)
        return CGRect(x: e.x + e.ancho * 0.70, y: g.minY + 8, width: e.ancho * 0.07,
                      height: g.height - 16)
    }

    static func centros(_ e: Elemento) -> [CGPoint] {
        let g = zonaGrafo(e)
        let r = radio(e)
        let x0 = g.minX + r + 10, x1 = g.maxX - r - 10
        let cy = g.minY + g.height * 0.42
        return (0..<5).map { CGPoint(x: x0 + (x1 - x0) * Double($0) / 4, y: cy) }
    }

    static func radio(_ e: Elemento) -> Double {
        min(zonaGrafo(e).height * 0.22, zonaGrafo(e).width / 12)
    }

    /// El punto del pulso en el tramo `seg` a la fracción `t`.
    static func puntoPulso(_ e: Elemento, seg: Int, t: Double) -> CGPoint {
        let c = centros(e), r = radio(e)
        func borde(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGPoint) {
            (CGPoint(x: a.x + r, y: a.y), CGPoint(x: b.x - r, y: b.y))
        }
        switch seg {
        case 0: let (p, q) = borde(c[0], c[1]); return lerp(p, q, t)
        case 1: let (p, q) = borde(c[1], c[2]); return lerp(p, q, t)
        case 2: let (p, q) = borde(c[2], c[3]); return lerp(p, q, t)
        case 4: let (p, q) = borde(c[3], c[4]); return lerp(p, q, t)
        default:                          // el regreso: curva por debajo
            let p = CGPoint(x: c[3].x, y: c[3].y + r), q = CGPoint(x: c[1].x, y: c[1].y + r)
            let ctrl = CGPoint(x: (p.x + q.x) / 2, y: p.y + r * 2.2)
            let u = 1 - t
            return CGPoint(x: u * u * p.x + 2 * u * t * ctrl.x + t * t * q.x,
                           y: u * u * p.y + 2 * u * t * ctrl.y + t * t * q.y)
        }
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Los dos botones, en la banda encima del dial. La geometría la calcula
    /// quien los pinta: dos piezas calculando dónde está un botón es la receta
    /// del botón que no se deja pulsar.
    /// La escala del elemento: las fuentes y los botones crecen con el alto
    /// (el retrato de pruebas mide 420; en un lienzo de dictado mide 900).
    static func k(_ e: Elemento) -> Double { max(1, min(3, e.alto / 420)) }

    static func zonaCorrer(_ e: Elemento) -> CGRect {
        let margen = min(40.0, e.ancho * 0.08), k = k(e)
        return CGRect(x: e.x + margen, y: e.y + e.alto - 26 - 22 - 14 - 44 * k, width: 180 * k, height: 44 * k)
    }
    static func zonaRegreso(_ e: Elemento) -> CGRect {
        let c = zonaCorrer(e), k = k(e)
        return CGRect(x: c.maxX + 14 * k, y: c.minY, width: 250 * k, height: 44 * k)
    }
    static func zonaReiniciar(_ e: Elemento) -> CGRect {
        let c = zonaRegreso(e), k = k(e)
        return CGRect(x: c.maxX + 14 * k, y: c.minY, width: 130 * k, height: 44 * k)
    }

    // ── EL PINTADO ──────────────────────────────────────────────────────────

    static func pintar(_ e: Elemento, _ ctx: CGContext, _ tema: Tema, vivo v: Vivo,
                       tenue: NSColor, medio: NSColor, fuerte: NSColor) {
        let ambar = tema.tintes["ambar"]?.trazo ?? fuerte
        let rojo = tema.tintes["rojo"]?.trazo ?? NSColor.red
        let verde = tema.tintes["verde"]?.trazo ?? NSColor.green
        let p = Pintor(ctx: ctx, tema: tema, camara: Camara(), tamano: CGSize(width: 1, height: 1))
        let k = k(e)
        var nom = EstiloTexto(); nom.peso = 800; nom.tamano = 15 * k
        var sub = EstiloTexto(); sub.peso = 600; sub.tamano = 11 * k
        var chico = EstiloTexto(); chico.peso = 700; chico.tamano = 13 * k
        var cifra = EstiloTexto(); cifra.peso = 800; cifra.tamano = 22 * k
        let c = centros(e), r = radio(e)

        ctx.saveGState()
        // ── las aristas ──
        ctx.setLineWidth(3 * k); ctx.setLineCap(.round)
        for i in 0..<4 {
            let a = CGPoint(x: c[i].x + r, y: c[i].y), b = CGPoint(x: c[i + 1].x - r, y: c[i + 1].y)
            let viva = v.corriendo && v.seg == (i < 3 ? i : 4)
            ctx.setStrokeColor((viva ? ambar : medio.withAlphaComponent(0.55)).cgColor)
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            flecha(ctx, b, hacia: CGPoint(x: 1, y: 0), color: viva ? ambar : medio.withAlphaComponent(0.55), k: k)
        }
        // ── la flecha de REGRESO ──
        do {
            let pIni = CGPoint(x: c[3].x, y: c[3].y + r), pFin = CGPoint(x: c[1].x, y: c[1].y + r)
            let ctrl = CGPoint(x: (pIni.x + pFin.x) / 2, y: pIni.y + r * 2.2)
            let viva = v.corriendo && v.seg == 3
            let color = !v.regreso ? medio.withAlphaComponent(0.22) : (viva ? ambar : fuerte)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineDash(phase: 0, lengths: v.regreso ? [12 * k, 9 * k] : [3 * k, 9 * k])
            ctx.move(to: pIni); ctx.addQuadCurve(to: pFin, control: ctrl); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            if v.regreso { flecha(ctx, pFin, hacia: CGPoint(x: 0, y: -1), color: color, k: k) }
            let txt = v.regreso ? "la flecha de REGRESO · sin ella no hay ciclo" : "sin flecha de regreso · esto es un DAG"
            // El rótulo va justo bajo el vientre de la curva (que cae a la
            // mitad del control), no en la banda de los botones.
            p.renglon(txt, chico, v.regreso ? ambar : tema.pieTexto,
                      x: c[1].x - 40, y: pIni.y + r * 1.1 + 10 * k, ancho: c[3].x - c[1].x + 80, alinea: "center")
        }
        // ── los nodos ──
        for (i, ctr) in c.enumerated() {
            let caliente = i == v.caliente && (v.corriendo || v.terminado)
            let llego = i == 4 && v.terminado && v.veredicto == "LLEGÓ"
            let caja = CGRect(x: ctr.x - r, y: ctr.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor((llego ? verde.withAlphaComponent(0.18) : caliente ? ambar.withAlphaComponent(0.18) : tenue).cgColor)
            ctx.fillEllipse(in: caja)
            ctx.setStrokeColor((llego ? verde : caliente ? ambar : fuerte).cgColor)
            ctx.setLineWidth((caliente || llego ? 5 : 3.5) * k); ctx.strokeEllipse(in: caja)
            p.renglon(nombres[i], nom, tema.tituloTexto, x: ctr.x - r, y: ctr.y - 16 * k, ancho: r * 2, alinea: "center")
            p.renglon(subtitulos[i], sub, tema.pieTexto, x: ctr.x - r, y: ctr.y + 6 * k, ancho: r * 2, alinea: "center")
        }
        // ── el pulso ──
        if v.corriendo, v.seg >= 0 {
            let q = puntoPulso(e, seg: v.seg, t: v.t)
            ctx.setShadow(offset: .zero, blur: 12 * k, color: ambar.withAlphaComponent(0.9).cgColor)
            ctx.setFillColor(ambar.cgColor)
            ctx.fillEllipse(in: CGRect(x: q.x - 9 * k, y: q.y - 9 * k, width: 18 * k, height: 18 * k))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        // ── el mensaje del comparador ──
        let g = zonaGrafo(e)
        let err = Int((error(v) * 100).rounded())
        var msg = ""
        if v.corriendo && v.caliente == 3 {
            msg = err > 0 ? "error = \(err) → " + (v.regreso ? "REGRESA" : "…no hay por dónde regresar") : "error = 0 → LLEGÓ"
        } else if v.terminado {
            msg = v.veredicto == "LLEGÓ"
                ? "los nodos no cambiaron; lo que corrió por ellos, sí · \(v.vueltas) vuelta" + (v.vueltas == 1 ? "" : "s")
                : "mismos nodos, una flecha menos: entregó lo que salió, no lo que se pidió"
        } else if v.seg < 0 {
            msg = "mapa (quieto) · pulsa CORRER"
        }
        p.renglon(msg, chico, v.terminado && v.veredicto != "LLEGÓ" ? rojo : tema.pieTexto,
                  x: g.minX, y: g.minY, ancho: g.width, alinea: "center")

        // ── el comparador: el riel, la referencia, el error ──
        let rl = zonaRiel(e)
        let pista = CGMutablePath(); pista.addRoundedRect(in: rl, cornerWidth: 8, cornerHeight: 8)
        ctx.addPath(pista); ctx.setFillColor(tema.rol("sticky").relleno.cgColor); ctx.fillPath()
        let hRes = rl.height * v.resultado
        let lleno = CGRect(x: rl.minX, y: rl.maxY - hRes, width: rl.width, height: hRes)
        ctx.saveGState(); ctx.addPath(pista); ctx.clip()
        ctx.setFillColor(medio.withAlphaComponent(0.75).cgColor); ctx.fill(lleno); ctx.restoreGState()
        ctx.addPath(pista); ctx.setStrokeColor(medio.withAlphaComponent(0.45).cgColor); ctx.setLineWidth(2); ctx.strokePath()
        let yRef = rl.maxY - rl.height * v.referencia
        ctx.setStrokeColor(ambar.cgColor); ctx.setLineWidth(4 * k)
        ctx.move(to: CGPoint(x: rl.minX - 8 * k, y: yRef)); ctx.addLine(to: CGPoint(x: rl.maxX + 8 * k, y: yRef)); ctx.strokePath()
        if err > 0 {
            ctx.setStrokeColor(rojo.cgColor); ctx.setLineWidth(3 * k)
            ctx.move(to: CGPoint(x: rl.midX, y: yRef)); ctx.addLine(to: CGPoint(x: rl.midX, y: rl.maxY - hRes)); ctx.strokePath()
        }
        // ── las cifras ──
        let cx = rl.maxX + 18 * k, cw = e.x + e.ancho - 16 - cx
        let filas: [(String, String, NSColor)] = [
            ("referencia", String(Int((v.referencia * 100).rounded())), ambar),
            ("resultado", String(Int((v.resultado * 100).rounded())), tema.tituloTexto),
            ("error", String(err), err > 0 ? rojo : verde),
            ("vueltas", String(v.vueltas), tema.tituloTexto),
            ("veredicto", v.veredicto.isEmpty ? "—" : v.veredicto,
             v.veredicto == "LLEGÓ" ? verde : (v.veredicto.isEmpty ? tema.pieTexto : rojo)),
        ]
        var y = rl.minY
        let dy = min(56.0 * k, rl.height / 5)
        for (nombre, val, col) in filas {
            p.renglon(nombre.uppercased(), sub, tema.pieTexto, x: cx, y: y, ancho: cw, alinea: "left")
            var est = cifra; if nombre == "veredicto" { est.tamano = 13 * k }
            p.renglon(val, est, col, x: cx, y: y + 24 * k, ancho: cw, alinea: "left")
            y += dy
        }

        // ── los botones ──
        boton(ctx, p, tema, zonaCorrer(e), v.corriendo ? "corriendo…" : "▶ CORRER",
              relleno: fuerte, texto: tema.lienzo, apagado: v.corriendo, k: k)
        boton(ctx, p, tema, zonaRegreso(e), "flecha de regreso: " + (v.regreso ? "SÍ" : "NO"),
              relleno: tema.lienzo, texto: v.regreso ? fuerte : tema.pieTexto, borde: v.regreso ? fuerte : medio, k: k)
        boton(ctx, p, tema, zonaReiniciar(e), "reiniciar", relleno: tema.lienzo, texto: tema.pieTexto, borde: medio, k: k)
        ctx.restoreGState()
    }

    private static func boton(_ ctx: CGContext, _ p: Pintor, _ tema: Tema, _ r: CGRect, _ texto: String,
                              relleno: NSColor, texto colorTexto: NSColor, borde: NSColor? = nil, apagado: Bool = false, k: Double = 1) {
        let camino = CGMutablePath(); camino.addRoundedRect(in: r, cornerWidth: 10 * k, cornerHeight: 10 * k)
        ctx.addPath(camino); ctx.setFillColor(relleno.withAlphaComponent(apagado ? 0.45 : 1).cgColor); ctx.fillPath()
        if let b = borde { ctx.addPath(camino); ctx.setStrokeColor(b.cgColor); ctx.setLineWidth(2 * k); ctx.strokePath() }
        var est = EstiloTexto(); est.peso = 800; est.tamano = 14 * k
        p.renglon(texto, est, colorTexto, x: r.minX, y: r.midY - 9 * k, ancho: r.width, alinea: "center")
    }

    private static func flecha(_ ctx: CGContext, _ punta: CGPoint, hacia d: CGPoint, color: NSColor, k: Double = 1) {
        let n = CGPoint(x: -d.y, y: d.x), l = 11.0 * k
        ctx.setFillColor(color.cgColor)
        ctx.move(to: punta)
        ctx.addLine(to: CGPoint(x: punta.x - d.x * l + n.x * l * 0.55, y: punta.y - d.y * l + n.y * l * 0.55))
        ctx.addLine(to: CGPoint(x: punta.x - d.x * l - n.x * l * 0.55, y: punta.y - d.y * l - n.y * l * 0.55))
        ctx.closePath(); ctx.fillPath()
    }
}
