import AppKit

/**
 * EDICION DE TEXTO: un campo REAL superpuesto, no un cursor dibujado.
 *
 * El cursor, la seleccion, el teclado del sistema, el dictado por voz, el
 * corrector y copiar/pegar son cosas que AppKit ya resuelve y que
 * reimplementar sobre un lienzo es una fuente inagotable de fallos. (Y en esta
 * casa el dictado importa: SFlow escribe por voz en cualquier campo del
 * sistema, y un editor dibujado a mano no seria uno de ellos.)
 *
 * ⚠️ LO QUE ESCRIBES TIENE QUE CAER DONDE VA A QUEDAR.
 *
 * Hasta el 20 ago 2026 el editor del lienzo web se pegaba arriba a la izquierda
 * y el motor pintaba el resultado CENTRADO: el texto SALTABA de sitio al
 * soltar. Un editor que no coincide con su resultado es peor que no tener
 * editor — obliga a escribir a ciegas y corregir despues. Aqui el contenedor
 * centra en vertical y el campo hereda la MISMA alineacion que usa el pintor,
 * leida del MISMO campo del modelo.
 *
 * REGLA: mientras se edita, el elemento NO se pinta en el lienzo, o se ve el
 * texto dos veces ligeramente desalineado.
 */
final class EditorTexto: NSView, NSTextViewDelegate {
    private let campo = NSTextView()
    private let scroll = NSScrollView()
    private var alGuardar: ((String) -> Void)?
    private var alCancelar: (() -> Void)?
    private var yaCerro = false

    /// El id que se esta editando. El lienzo lo consulta para NO pintarlo.
    private(set) var editando: String?
    /// Este editor admite saltos de línea con Enter (bloques de código).
    private var multilinea = false

    init(elemento e: Elemento, tema: Tema, camara: Camara, viewport: NSSize,
         guardar: @escaping (String) -> Void, cancelar: @escaping () -> Void) {
        editando = e.id
        alGuardar = guardar
        alCancelar = cancelar

        /*
         * ⚠️ UN BLOQUE DE CÓDIGO NO ES UNA CAJA DE TEXTO CORTA (26 ago 2026).
         *
         * Daniel: *"le doy doble clic para intentar entrar y poder modificarlo
         * o copiarlo, y no me lo permite"*. Además del guard que lo bloqueaba,
         * aquí había dos cosas mal para este tipo: el editor caía al estilo por
         * defecto (14 px, negrita, sans) en vez del suyo —así que el texto
         * SALTABA de tamaño y de tipografía al entrar— y Enter guardaba en vez
         * de hacer salto de línea. En un prompt de ocho renglones, Enter
         * teniendo que ser ⇧Enter es inutilizable.
         *
         * En código: la tipografía es la del elemento en mono, Enter es un
         * salto de línea, y se guarda al salir (clic fuera o ⌘Enter).
         */
        let esCodigo = e.tipo == "code"
        let est: EstiloTexto = {
            if e.tipo == "text" { return e.estilo }
            if esCodigo { var s = e.estilo; s.familia = "jetbrains-mono"; return s }
            if let p = e.textoLigado?.first { return p.estilo }
            var s = EstiloTexto(); s.peso = 800; s.tamano = 14; return s
        }()
        let z = camara.zoom
        // Una figura centra en vertical; un bloque de texto crece hacia abajo
        // desde su borde superior, que es lo que su arrastre definio.
        let centraVertical = e.tipo == "shape"
        // El pintor del código compone con 14 px de margen: el editor tiene que
        // caer EN EL MISMO SITIO o el texto se desplaza al entrar y al salir.
        let pad: Double = e.tipo == "shape" ? Crear.PAD : (esCodigo ? 14 : 0)

        func aPantalla(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - camara.x) * z + viewport.width / 2,
                    y: (p.y - camara.y) * z + viewport.height / 2)
        }
        let esquina = aPantalla(CGPoint(x: e.x + pad, y: e.y + pad))
        let w = max(60, (e.ancho - pad * 2) * z)
        let h = max(28, (e.alto - pad * 2) * z)
        // La Y de AppKit crece hacia ARRIBA y la del lienzo hacia abajo.
        super.init(frame: NSRect(x: esquina.x, y: viewport.height - esquina.y - h, width: w, height: h))

        /*
         * ⚠️ SIN MARCO. Daniel: *"quita el rectángulo morado interno del texto,
         * solo deja el externo, y obviamente el cursor parpadeando".*
         *
         * Tenía razón y el motivo es de fondo: la figura YA está seleccionada y
         * su caja morada ya lo dice. Un segundo rectángulo dentro del primero no
         * añade información — añade una figura que no existe, y en una nota de
         * 220 px el marco interno parece parte del dibujo.
         *
         * Lo que SÍ hace falta es la señal de que está esperando texto, y esa es
         * el cursor: parpadea, no ocupa sitio, y es la convención que cualquier
         * mano ya conoce.
         */
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        campo.string = e.textoEditable
        campo.font = Fuentes.fuente(familia: est.familia, peso: est.peso,
                                    tamano: est.tamano * z, cursiva: est.cursiva) as NSFont?
        campo.textColor = tema.tituloTexto
        // El cursor en el acento: sobre una nota amarilla o una figura clara, el
        // cursor negro del sistema se pierde entre el texto.
        campo.insertionPointColor = tema.acento
        campo.backgroundColor = .clear
        campo.drawsBackground = false
        campo.isRichText = false
        campo.isAutomaticQuoteSubstitutionEnabled = false
        campo.alignment = switch e.alineacion {
            case "center": .center
            case "right": .right
            default: .left
        }
        campo.textContainerInset = .zero
        campo.textContainer?.lineFragmentPadding = 0
        campo.delegate = self
        campo.isVerticallyResizable = true
        campo.textContainer?.widthTracksTextView = true

        scroll.frame = bounds
        scroll.documentView = campo
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        addSubview(scroll)
        multilinea = esCodigo
        acomodarVertical(centraVertical)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Centra el texto en vertical dentro de la figura, como lo hace el pintor.
    private func acomodarVertical(_ centrar: Bool) {
        guard centrar, let lm = campo.layoutManager, let tc = campo.textContainer else { return }
        lm.ensureLayout(for: tc)
        let alto = lm.usedRect(for: tc).height
        let hueco = max(0, (bounds.height - alto) / 2)
        campo.textContainerInset = NSSize(width: 0, height: hueco)
    }

    func enfocar() { window?.makeFirstResponder(campo) }

    func textDidChange(_ n: Notification) { acomodarVertical(true) }

    /// Enter guarda; Shift+Enter hace salto de linea. Es la convencion de
    /// cualquier herramienta con cajas de texto cortas.
    func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            // En CÓDIGO la convención se invierte: Enter salta de línea y se
            // guarda con ⌘Enter o saliendo. Ver el comentario del init.
            if multilinea && !NSEvent.modifierFlags.contains(.command) {
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            if NSEvent.modifierFlags.contains(.shift) {
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            cerrar(guardando: true)
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { cerrar(guardando: false); return true }
        return false
    }

    /// Perder el foco GUARDA. Cancelar solo con Escape: si un clic fuera
    /// descartara, escribir y tocar el lienzo perderia el trabajo sin aviso.
    func cerrarPorFoco() { cerrar(guardando: true) }

    private func cerrar(guardando: Bool) {
        guard !yaCerro else { return }
        yaCerro = true
        let t = campo.string
        removeFromSuperview()
        guardando ? alGuardar?(t) : alCancelar?()
    }
}
