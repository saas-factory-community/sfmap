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
    private var centraVertical = false
    private var colorExplicito: NSColor?
    private var cajaMundo = CGRect.zero
    /// TARJETA: la línea 1 es el título (su fuente) y las demás son items (la
    /// suya). Sin esto, todo el campo heredaba la fuente del título y "al hacer
    /// doble clic todas se ponen bold" (Daniel, 31 ago 2026) — el editor
    /// enseñaba una jerarquía que el pintor no tiene.
    private var fuenteTitulo: NSFont?
    private var fuenteItem: NSFont?

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
        let z = 1.0 // El editor se compone en unidades del documento; AppKit escala la vista.
        // Una figura centra en vertical; un bloque de texto crece hacia abajo
        // desde su borde superior, que es lo que su arrastre definio.
        centraVertical = e.tipo == "shape"
        // El pintor del código compone con 14 px de margen: el editor tiene que
        // caer EN EL MISMO SITIO o el texto se desplaza al entrar y al salir.
        let pad: Double = e.tipo == "shape" ? Crear.PAD : (esCodigo ? 14 : 0)

        let w = max(1, e.ancho - pad * 2)
        let h = max(28, e.alto - pad * 2)
        cajaMundo = CGRect(x: e.x + pad, y: e.y + pad, width: w, height: h)
        super.init(frame: CGRect(origin: .zero, size: cajaMundo.size))
        autoresizesSubviews = false

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

        // El documento tiene el ancho visible desde antes del primer cursor.
        appearance = NSAppearance(named: tema.nombre == "oscuro" ? .darkAqua : .aqua)
        campo.usesAdaptiveColorMappingForDarkAppearance = false
        campo.isEditable = true
        campo.isSelectable = true
        campo.allowsUndo = true
        campo.frame = bounds
        campo.minSize = NSSize(width: 0, height: h)
        campo.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        campo.isHorizontallyResizable = false
        campo.autoresizingMask = [.width]
        campo.string = e.textoEditable
        campo.font = Fuentes.fuente(familia: est.familia, peso: est.peso,
                                    tamano: est.tamano * z, cursiva: est.cursiva) as NSFont?
        colorExplicito = e.colorTexto.flatMap { NSColor(hex: $0) }
        campo.textColor = colorExplicito ?? tema.tituloTexto
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
        // También el párrafo VACÍO debe heredar la alineación: determina
        // dónde nace el cursor antes de que exista el primer carácter.
        let parrafo = NSMutableParagraphStyle()
        parrafo.alignment = campo.alignment
        campo.defaultParagraphStyle = parrafo
        campo.typingAttributes = [.font: campo.font!, .foregroundColor: campo.textColor!,
                                  .paragraphStyle: parrafo, .kern: (est.espaciado ?? 0) * z]
        campo.textContainerInset = .zero
        campo.textContainer?.lineFragmentPadding = 0
        campo.delegate = self
        campo.isVerticallyResizable = true
        campo.textContainer?.widthTracksTextView = true
        campo.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)

        scroll.frame = bounds
        scroll.documentView = campo
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        addSubview(scroll)
        // Una TARJETA (título + items) también es multilínea: Enter agrega un
        // item; se guarda con ⌘Enter o saliendo. Ver Edicion.textoEditable.
        multilinea = esCodigo || e.esTarjeta
        if e.esTarjeta {
            let partes = e.textoLigado ?? []
            let estT = partes.first { $0.kind == "title" }?.estilo ?? est
            let estI = partes.first { $0.kind == "item" }?.estilo ?? est
            fuenteTitulo = Fuentes.fuente(familia: estT.familia, peso: estT.peso,
                                          tamano: estT.tamano * z, cursiva: estT.cursiva) as NSFont?
            fuenteItem = Fuentes.fuente(familia: estI.familia, peso: estI.peso,
                                        tamano: estI.tamano * z, cursiva: estI.cursiva) as NSFont?
            vestirLineas()
        }
        acomodarVertical()
        actualizarCamara(camara, viewport: viewport)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Conserva texto, selección, foco y undo. Cambia la transformación de
    /// toda la vista, incluido el cursor, en vez de reconstruir el NSTextView.
    func actualizarCamara(_ camara: Camara, viewport: NSSize) {
        let z = camara.zoom
        frame = CGRect(x: (cajaMundo.minX - camara.x) * z + viewport.width / 2,
                       y: viewport.height / 2 - (cajaMundo.maxY - camara.y) * z,
                       width: cajaMundo.width * z, height: cajaMundo.height * z)
        bounds = CGRect(origin: .zero, size: cajaMundo.size)
        needsDisplay = true
    }

    /// Centra el texto en vertical dentro de la figura, como lo hace el pintor.
    private func acomodarVertical() {
        guard centraVertical, let lm = campo.layoutManager, let tc = campo.textContainer else { return }
        lm.ensureLayout(for: tc)
        let alto = lm.usedRect(for: tc).height
        let hueco = max(0, (bounds.height - alto) / 2)
        campo.textContainerInset = NSSize(width: 0, height: hueco)
    }

    /// El tema cambia también DURANTE la edición. El editor es hermano del
    /// lienzo: no hereda sus colores al repintarlo.
    func actualizarTema(_ tema: Tema) {
        appearance = NSAppearance(named: tema.nombre == "oscuro" ? .darkAqua : .aqua)
        let color = colorExplicito ?? tema.tituloTexto
        campo.textColor = color
        campo.typingAttributes[.foregroundColor] = color
        campo.insertionPointColor = tema.acento
        campo.needsDisplay = true
    }

    func enfocar() { window?.makeFirstResponder(campo) }

    /// En una tarjeta cada línea viste SU fuente: la 1 el título, el resto el
    /// item. Se re-aplica en cada tecleo porque el texto plano hereda la fuente
    /// del punto de inserción y una línea nueva nacería con la equivocada.
    private func vestirLineas() {
        guard let ft = fuenteTitulo, let fi = fuenteItem,
              let ts = campo.textStorage else { return }
        let s = campo.string as NSString
        ts.beginEditing()
        var pos = 0, linea = 0
        while pos < s.length {
            let r = s.lineRange(for: NSRange(location: pos, length: 0))
            ts.addAttribute(.font, value: linea == 0 ? ft : fi, range: r)
            pos = NSMaxRange(r); linea += 1
        }
        ts.endEditing()
        campo.typingAttributes[.font] = linea <= 1 ? ft : fi
    }

    func textDidChange(_ n: Notification) { vestirLineas(); acomodarVertical() }

    /// Enter guarda; Shift+Enter hace salto de linea. Es la convencion de
    /// cualquier herramienta con cajas de texto cortas.
    func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            // Los modificadores pertenecen a ESTA tecla, no al teclado físico
            // que puede haber cambiado mientras AppKit entrega el comando.
            let modificadores = NSApp.currentEvent?.modifierFlags ?? []
            // En CÓDIGO la convención se invierte: Enter salta de línea y se
            // guarda con ⌘Enter o saliendo. Ver el comentario del init.
            if multilinea && !modificadores.contains(.command) {
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            if modificadores.contains(.shift) {
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
