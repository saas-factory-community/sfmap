import AppKit

/**
 * LA FRANJA de la barra de titulo: doble clic AMPLIA la ventana.
 *
 * Con `fullSizeContentView` el contenido llega hasta arriba y esta franja se
 * come el doble clic que macOS reservaba para el zoom. Devolverselo no es un
 * detalle: es el unico gesto con el que se agranda una ventana sin apuntar a un
 * borde de 3 px.
 */
final class FranjaTitulo: NSView {
    /**
     * ⚠️ Y SE PINTA SOLA, con el bisel.
     *
     * Era un `layer.backgroundColor` plano puesto desde fuera, y eso costó dos
     * cosas a la vez. Una: al pasar el resto del cromo a bisel, esta fila se
     * quedó siendo la única superficie lisa de la ventana — la barra de título
     * y el panel de abajo son LA MISMA placa y se veían de dos materiales.
     * Dos, y peor: quien la pintaba lo hacía ANTES de cambiar el tema, así que
     * en oscuro seguía blanca. Daniel: *"asegúrate de que el header se adapte
     * bien en tema oscuro"*.
     *
     * Pintándose ella misma en `draw`, el orden deja de importar: repinta cuando
     * le cambian el tema, como todas las demás.
     */
    var tema: Tema = .claro { didSet { needsDisplay = true } }

    override func draw(_ r: NSRect) { Estilo.pintarBisel(self, tema, radio: 0, borde: false) }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount >= 2 { window?.zoom(nil) }
    }
}

/**
 * LA BARRA DE TÍTULO, al estilo de sfcal.
 *
 * Daniel, con sfcal delante: *"nota cómo el header está alineado con los iconos
 * de semáforo… nota cómo todo luce simétrico"*. Y: *"alinearía el botón del
 * folder así como el texto, quitaría el número del cuatro, lo veo innecesario"*.
 *
 * QUÉ CAMBIÓ Y POR QUÉ:
 *
 * · **Se alinea con los semáforos.** Antes era una tarjeta flotante que empezaba
 *   78 px a su derecha y 14 más abajo: dos elementos de cromo en dos líneas
 *   distintas leyendo como dos aplicaciones. Una fila de barra de título es UNA
 *   fila, y los botones de macOS son el ancla de esa fila, no un obstáculo que
 *   rodear.
 *
 * · **Se fue el contador.** "· 38" es un dato que no cambia ninguna decisión: no
 *   se actúa sobre él, no avisa de nada, y le roba sitio al único texto que sí
 *   identifica lo que estás mirando.
 *
 * · **La identidad de la app vive en el PANEL**, no aquí. Cuando el panel se
 *   abre, ahí arriba aparecen el icono y el nombre —como en sfcal— y esta fila
 *   se corre a su derecha. La barra de título dice qué DOCUMENTO miras; el panel
 *   dice en qué APLICACIÓN estás. Son dos preguntas y cada una tiene su sitio.
 */
final class HeaderPulsable: NSView {
    static let ALTO: CGFloat = 52

    var alPulsar: (() -> Void)?
    var tema: Tema = .claro { didSet { repintar() } }
    var abierto = false { didSet { repintar() } }

    private let toggle = BotonPlano(icono: Icono.panel, ancho: 30, alto: 30)
    private let ruta = NSTextField(labelWithString: "")
    private let separador = NSTextField(labelWithString: "/")
    private let nombre = NSTextField(labelWithString: "sfmap")

    /// Cuánto ocupa con su contenido actual. La fila se ajusta al nombre en vez
    /// de reservar un ancho fijo: 300 px con la palabra "Julio" dentro es hueco.
    var anchoIdeal: CGFloat {
        let r = ruta.stringValue.isEmpty ? 0 : ruta.attributedStringValue.size().width + 16
        return 38 + r + nombre.attributedStringValue.size().width + 22
    }


    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: Self.ALTO))
        /*
         * SIN GLOBO en el interruptor del panel.
         *
         * Daniel: *"no me gusta el hover que dice Lienzos, es estorboso"*. Y es
         * cierto: vive pegado al título del documento, así que aparece cada vez
         * que el ratón pasa camino de otra cosa, y tapa justo lo que ibas a
         * leer. Un globo se gana su sitio cuando el icono es ambiguo; el de la
         * barra lateral es el mismo que usa todo macOS.
         */
        toggle.globo = nil
        toggle.alPulsar = { [weak self] in self?.alPulsar?() }
        addSubview(toggle)
        for t in [ruta, separador, nombre] { addSubview(t) }
        repintar()
    }
    required init?(coder: NSCoder) { fatalError() }

    func poner(nombre n: String, carpeta: String?) {
        nombre.stringValue = n
        ruta.stringValue = carpeta ?? ""
        repintar()
        needsLayout = true
    }

    /*
     * DOBLE CLIC EN EL TÍTULO = RENOMBRAR.
     *
     * Es donde la mano lo busca —Finder, Xcode y cualquier app de documentos lo
     * hacen así— y hasta ahora renombrar solo existía escondido en el menú ⋯ de
     * la fila del panel, que hay que abrir para descubrir.
     *
     * ⚠️ `NSTextField(labelWithString:)` se traga el `mouseDown` y no lo pasa al
     * padre, así que el doble clic sobre el nombre no llegaba a ningún sitio. El
     * `hitTest` devuelve `self` para la zona del título —no para el botón, que
     * sí tiene que recibir sus clics— y la fila entera se vuelve pulsable.
     */
    override func hitTest(_ punto: NSPoint) -> NSView? {
        let local = convert(punto, from: superview)
        if toggle.frame.contains(local) { return toggle }
        return bounds.contains(local) ? self : nil
    }

    /**
     * CLIC = abrir el panel. DOBLE CLIC = AMPLIAR LA VENTANA.
     *
     * Daniel, tres veces: *"sigo dando clic al header y sigue sin ampliarse la
     * sección automáticamente. Doble clic, te acuerdas"*. Es el gesto de macOS
     * de toda la vida sobre la barra de título, y aqui NO llegaba: la fila es
     * una vista propia que se comia el evento antes de que la ventana lo viera.
     *
     * Renombrar se mudo al menu ⋯ de la fila del panel —donde ya vivia— porque
     * los dos gestos son el mismo y el de la ventana es el que espera la mano.
     */
    override func mouseDown(with e: NSEvent) {
        if e.clickCount >= 2 { window?.zoom(nil); return }
        alPulsar?()
    }

    override func layout() {
        super.layout()
        let cy = (bounds.height - 30) / 2
        toggle.frame = NSRect(x: 0, y: cy, width: 30, height: 30)
        var x: CGFloat = 38
        ruta.isHidden = ruta.stringValue.isEmpty
        separador.isHidden = ruta.isHidden
        if !ruta.isHidden {
            let w = ruta.attributedStringValue.size().width
            ruta.frame = NSRect(x: x, y: bounds.midY - 9, width: w + 2, height: 18)
            separador.frame = NSRect(x: x + w + 5, y: bounds.midY - 9, width: 8, height: 18)
            x += w + 16
        }
        // El NOMBRE nunca cede: es lo único que dice qué documento estás
        // mirando. Si algo tiene que recortarse es el prefijo de carpeta.
        let n = nombre.attributedStringValue.size().width
        nombre.frame = NSRect(x: x, y: bounds.midY - 10, width: min(n + 10, bounds.width - x), height: 20)
    }

    private func repintar() {
        // SIN tarjeta: es una fila de barra de título, no un objeto flotante.
        // Un fondo aquí volvería a partir la fila en dos superficies.
        toggle.tema = tema
        toggle.activo = abierto
        nombre.font = Estilo.fuente(13.5, 700); nombre.textColor = tema.tituloTexto
        ruta.font = Estilo.fuente(13, 500); ruta.textColor = tema.pieTexto
        separador.font = Estilo.fuente(13, 400); separador.textColor = tema.pieTexto.withAlphaComponent(0.5)
        nombre.lineBreakMode = .byTruncatingMiddle
        nombre.toolTip = "Doble clic para ampliar la ventana"
    }
}
