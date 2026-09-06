import AppKit
import CoreGraphics

/**
 * ENACTAR 2D — el lienzo que ENSEÑA moviéndose. `F5` entra, `→` avanza.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * POR QUÉ EXISTE (y por qué NO es un WKWebView)
 * ════════════════════════════════════════════════════════════════════════════
 *
 * Daniel, 26 ago 2026, dictando el curso v2 sobre el lienzo del comparador:
 * *"si yo lo veo de lejos, esto se ve aburrido… le falta dinamismo, le faltan
 * imágenes, le falta ENACTAR elementos 2D"*. Y acto seguido: *"podemos insertar
 * HTML pero son estáticos… por algún lado del repositorio vas a encontrar el
 * cómo de los pergaminos vivos"*.
 *
 * La lectura fácil habría sido resucitar los embeds vivos y meter una página
 * animada por elemento. **No.** Ya hay lápida y es SUYA (`Markdown.swift`, 20
 * ago 2026): *"lo siento medio buggy, prefiero el fucking localhost simple"*.
 * Y el costo no ha cambiado: un WebKit por tarjeta es el arranque de un
 * navegador entero por documento, justo en la app cuya razón de ser es abrir
 * instantáneo. Un lienzo con diez animaciones sería un lienzo que ya no abre.
 *
 * Lo que se pide de verdad no es "HTML que se mueva": es que **el concepto
 * llegue por partes y con gesto**, que es como se enseña en un pizarrón. Eso el
 * pintor nativo ya sabe hacerlo — solo le faltaba un reloj y un orden. Sin
 * proceso extra, sin red, sin dependencias, y grabable dentro de sfmap, que es
 * donde Daniel graba todo el curso.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * EL CONTRATO
 * ════════════════════════════════════════════════════════════════════════════
 *
 * Un elemento declara su papel en la clase con `escena` en su JSON:
 *
 *     "escena": { "orden": 3, "gesto": "subir" }
 *
 * · `orden` 0 (o sin `escena`) = **el decorado**: se pinta siempre, desde el
 *   primer fotograma. Los territorios, la cabecera y las cotas viven aquí — si
 *   el marco también apareciera, el alumno perdería el mapa.
 * · `orden` N ≥ 1 = **la clase**: no existe hasta que el paso llega a N. En su
 *   paso entra ANIMADO; después se queda quieto y sólido.
 *
 * Fuera del modo (`F5`) TODO se pinta normal: el lienzo sigue siendo el mismo
 * documento, y un export nunca sale a medio revelar.
 *
 * ⚠️ NADA DE ESTO TOCA EL DOCUMENTO. El paso vive en memoria, como el zoom. Un
 * revelado a medias jamás se guarda en `draw` (misma regla que el Cronista).
 */
enum Enactar {

    /// Cuánto dura la entrada de UN paso. Medido contra el norte de Iman: por
    /// debajo de ~0.35 s el ojo no alcanza a leer el gesto y parece un salto;
    /// por encima de ~0.6 s el que graba espera a la animación.
    static let duracion: TimeInterval = 0.45

    /// El desplazamiento de entrada, en unidades del lienzo. Suficiente para
    /// leerse como movimiento, corto para no descolocar la composición.
    static let recorrido: Double = 46

    // ── LOS GESTOS ──────────────────────────────────────────────────────────
    /**
     * Un gesto es un ADVERBIO, no un adorno: dice CÓMO llega la idea.
     *
     * · `aparecer` — llega sin más. El default honesto.
     * · `subir` / `bajar` / `izq` / `der` — llega DESDE algún lado; se usa
     *   cuando la dirección significa (lo que sube es consecuencia, lo que
     *   entra por la izquierda es lo anterior en el tiempo).
     * · `crecer`  — llega desde su propio centro. Para lo que ES un tamaño.
     * · `trazar`  — se DIBUJA de izquierda a derecha, como una pluma. Para
     *   flechas, cotas, filetes y curvas: la línea que se traza dice
     *   "esto avanza" de una forma que un fundido no dice.
     */
    enum Gesto: String {
        case aparecer, subir, bajar, izq, der, crecer, trazar

        static func de(_ s: String?) -> Gesto { Gesto(rawValue: s ?? "") ?? .aparecer }
    }

    // ── EL ESTADO (en memoria, nunca en el documento) ────────────────────────
    final class Estado {
        /// ¿Está el lienzo en modo clase?
        private(set) var activo = false
        /// Paso visible. 0 = sólo el decorado.
        private(set) var paso = 0
        /// El paso más alto declarado en la página; se recalcula al entrar.
        private(set) var tope = 0
        /// Cuándo empezó la animación del paso actual.
        private var t0: TimeInterval = 0
        private var reloj: Timer?
        /// Lo llama el reloj: el lienzo se repinta.
        var alRepintar: (() -> Void)?

        var animando: Bool { activo && progreso < 1 }

        /// 0…1 de la entrada del paso actual.
        var progreso: Double {
            guard t0 > 0 else { return 1 }
            let d = (ProcessInfo.processInfo.systemUptime - t0) / Enactar.duracion
            return max(0, min(1, d))
        }

        func entrar(tope: Int) {
            self.tope = max(0, tope)
            activo = true
            paso = 0
            t0 = 0
            alRepintar?()
        }

        func salir() {
            activo = false
            paso = 0
            t0 = 0
            reloj?.invalidate(); reloj = nil
            alRepintar?()
        }

        /// Avanza un paso y arranca su animación. Devuelve false si ya no hay.
        @discardableResult
        func avanzar() -> Bool {
            guard activo, paso < tope else { return false }
            paso += 1
            arrancarReloj()
            return true
        }

        /// Retrocede SIN animar: rebobinar es una corrección, no una clase.
        @discardableResult
        func retroceder() -> Bool {
            guard activo, paso > 0 else { return false }
            paso -= 1
            t0 = 0
            reloj?.invalidate(); reloj = nil
            alRepintar?()
            return true
        }

        /// Todo de golpe: el remate, y el estado en que conviene exportar.
        func revelarTodo() {
            guard activo else { return }
            paso = tope
            t0 = 0
            reloj?.invalidate(); reloj = nil
            alRepintar?()
        }

        private func arrancarReloj() {
            reloj?.invalidate()
            t0 = ProcessInfo.processInfo.systemUptime
            /*
             * 60 fps mientras dura la entrada, y el reloj SE MUERE al acabar.
             * Un temporizador que sigue latiendo con el lienzo quieto es la
             * versión de escritorio del órgano zombie: gasta batería y repinta
             * una página que no cambió.
             */
            reloj = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
                guard let s = self else { t.invalidate(); return }
                s.alRepintar?()
                if s.progreso >= 1 { t.invalidate(); s.reloj = nil }
            }
            if let r = reloj { RunLoop.main.add(r, forMode: .eventTracking) }
            alRepintar?()
        }
    }

    // ── LECTURA DEL ELEMENTO ────────────────────────────────────────────────

    /// El paso que declara un elemento. 0 = decorado (siempre visible).
    static func orden(_ e: Elemento) -> Int {
        guard let n = e.crudo["escena"]?["orden"]?.num else { return 0 }
        return max(0, Int(n))
    }

    static func gesto(_ e: Elemento) -> Gesto {
        Gesto.de(e.crudo["escena"]?["gesto"]?.s)
    }

    /// El paso más alto declarado en la página.
    static func tope(_ els: [Elemento]) -> Int {
        els.reduce(0) { max($0, orden($1)) }
    }

    // ── EL PINTADO ──────────────────────────────────────────────────────────

    /**
     * Envuelve el pintado de UN elemento con su estado de clase.
     *
     * Devuelve `false` si el elemento todavía no existe (y entonces no se
     * pinta nada). Si existe, ejecuta `cuerpo` con la transformación de entrada
     * aplicada.
     *
     * ⚠️ El fundido va por CAPA DE TRANSPARENCIA, no por `setAlpha`. Cada
     * pintor abre con `ctx.setAlpha(e.opacidad)` —pisaría cualquier alpha que
     * pusiéramos antes—; una capa, en cambio, compone el grupo entero contra el
     * alpha vigente al abrirla. Sin esto el fundido sencillamente no ocurre.
     */
    static func conEscena(_ ctx: CGContext, _ e: Elemento, _ st: Estado,
                          _ cuerpo: () -> Void) -> Bool {
        guard st.activo else { cuerpo(); return true }
        let n = orden(e)
        if n == 0 || n < st.paso { cuerpo(); return true }   // decorado o ya dicho
        if n > st.paso { return false }                       // todavía no existe

        let p = suave(st.progreso)
        let g = gesto(e)
        ctx.saveGState()
        ctx.setAlpha(g == .trazar ? 1 : p)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        switch g {
        case .aparecer:
            cuerpo()
        case .subir:  ctx.translateBy(x: 0, y: recorrido * (1 - p)); cuerpo()
        case .bajar:  ctx.translateBy(x: 0, y: -recorrido * (1 - p)); cuerpo()
        case .izq:    ctx.translateBy(x: -recorrido * (1 - p), y: 0); cuerpo()
        case .der:    ctx.translateBy(x: recorrido * (1 - p), y: 0); cuerpo()
        case .crecer:
            // Crece desde su propio centro, no desde la esquina: si no, la
            // caja "resbala" hacia su sitio y el gesto deja de leerse como
            // tamaño.
            let c = CGPoint(x: e.x + e.ancho / 2, y: e.y + e.alto / 2)
            let k = 0.90 + 0.10 * p
            ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -c.x, y: -c.y)
            cuerpo()
        case .trazar:
            // La pluma: se recorta por una ventana que crece a lo ancho. Con
            // un margen generoso arriba y abajo para no cortar puntas de
            // flecha ni tildes.
            ctx.clip(to: CGRect(x: e.x - 40, y: e.y - 60,
                                width: (e.ancho + 80) * p, height: e.alto + 120))
            cuerpo()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        return true
    }

    /// Suavizado de entrada (ease-out cúbico). Una rampa lineal se percibe
    /// mecánica: el ojo lee "animación de software", no "gesto de mano".
    static func suave(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return 1 - pow(1 - x, 3)
    }
}
