import AppKit

/// Las 21 herramientas. El identificador es el mismo que el del lienzo web.
enum Herramienta: String, CaseIterable {
    case seleccionar = "select", mano = "pan"
    case nota = "sticky", texto = "text"
    case rect, ellipse, triangle, diamond, star, pill, hexagon, arrow
    case seccion = "section"
    /*
     * TRES FORMAS DE FLECHA, no una.
     *
     * Daniel: *"acuérdate que son flechas, con todo lo que la configuración de
     * flechas conlleva"*. La forma del trazado —codos, recta, curva— es la
     * decisión que se toma ANTES de trazar, igual que elegir rectángulo o
     * círculo. Tenerla solo en la barra contextual obliga a dibujar la flecha
     * mal y corregirla después.
     */
    case conector = "connector", conectorRecto = "connector-recta", conectorCurvo = "connector-curva"
    case lapiz = "pen", marcador = "highlighter", goma = "eraser"
    case tabla = "table", imagen = "image", embed, codigo = "code"

    /// Las que se dibujan ARRASTRANDO para definir su tamaño.
    static let deArrastre: Set<Herramienta> = [.rect, .ellipse, .triangle, .diamond, .star,
                                               .pill, .hexagon, .arrow, .seccion, .texto]
    /// Las que crean con UN toque.
    static let deToque: Set<Herramienta> = [.nota, .tabla, .embed, .codigo]
    /// Las tres flechas. Comparten el gesto entero; solo cambia por dónde va la
    /// línea, y eso se guarda en el conector como `routing`.
    static let flechas: Set<Herramienta> = [.conector, .conectorRecto, .conectorCurvo]
    var ruteo: String {
        switch self {
        case .conectorRecto: return "recta"
        case .conectorCurvo: return "curva"
        default: return "ortogonal"
        }
    }

    /// Las figuras, que comparten todo menos su geometria.
    static let figuras: Set<Herramienta> = [.rect, .ellipse, .triangle, .diamond, .star, .pill, .hexagon, .arrow]

    var icono: NSImage {
        switch self {
        case .seleccionar: return Icono.cursor
        case .mano: return Icono.mano
        case .nota: return Icono.nota
        case .texto: return Icono.textoT
        case .rect: return Icono.cuadrado
        case .ellipse: return Icono.circulo
        case .triangle: return Icono.triangulo
        case .diamond: return Icono.rombo
        case .star: return Icono.estrella
        case .pill: return Icono.pildora
        case .hexagon: return Icono.hexagono
        case .arrow: return Icono.flechaFigura
        case .seccion: return Icono.seccion
        case .conector: return Icono.flecha("codos")
        case .conectorRecto: return Icono.flecha("recta")
        case .conectorCurvo: return Icono.flecha("curva")
        case .lapiz: return Icono.lapiz
        case .marcador: return Icono.marcador
        case .goma: return Icono.goma
        case .tabla: return Icono.tabla
        case .imagen: return Icono.imagen
        case .embed: return Icono.embed
        case .codigo: return Icono.codigo
        }
    }

    var nombre: String {
        switch self {
        case .seleccionar: return "Seleccionar"
        case .mano: return "Mano"
        case .nota: return "Nota"
        case .texto: return "Texto"
        case .rect: return "Rectángulo"
        case .ellipse: return "Círculo"
        case .triangle: return "Triángulo"
        case .diamond: return "Rombo"
        case .star: return "Estrella"
        case .pill: return "Píldora"
        case .hexagon: return "Hexágono"
        case .arrow: return "Flecha"
        case .seccion: return "Sección"
        case .conector: return "Flecha con codos"
        case .conectorRecto: return "Flecha recta"
        case .conectorCurvo: return "Flecha curva"
        case .lapiz: return "Lápiz"
        case .marcador: return "Marcador"
        case .goma: return "Goma"
        case .tabla: return "Tabla"
        case .imagen: return "Imagen"
        case .embed: return "Embed"
        case .codigo: return "Código"
        }
    }

    /**
     * EL NOMBRE CORTO, para el rótulo del rail.
     *
     * La tira mide 58 px: "Flecha con codos" no cabe ahí ni encogida hasta lo
     * ilegible. Solo las que no son UNA palabra necesitan versión corta; el
     * resto usa su nombre de siempre, y el largo sobrevive entero en el globo.
     */
    // `rotulo` sobrevive para el globo y el desplegable; el rail ya no lo pinta.
    var rotulo: String {
        switch self {
        case .seleccionar:    return "Selección"
        case .rect:           return "Caja"
        case .conector:       return "Codos"
        case .conectorRecto:  return "Recta"
        case .conectorCurvo:  return "Curva"
        default:              return nombre
        }
    }

    var tecla: String {
        switch self {
        case .seleccionar: return "V"
        case .mano: return "H"
        case .nota: return "N"
        /*
         * ⚠️ EL TEXTO YA NO ES LA T. Daniel: *"permíteme con T cambiar de tema,
         * súper sencillo"*. Y en español las dos palabras empiezan igual, así
         * que había que elegir: la T se la queda el TEMA, que es lo que él
         * cambia mientras graba, y el texto se muda a la L de *letra*.
         *
         * Es coherente con cómo usa la app: los diagramas los escribe el agente,
         * no la mano — la herramienta de texto es para anotar de vez en cuando y
         * vive a un clic en el rail. El tema, en cambio, se toca con la cámara
         * encendida y ahí una tecla suelta vale más que un menú.
         */
        case .texto: return "L"
        case .rect: return "R"
        case .ellipse: return "O"
        case .conector: return "C"
        case .seccion: return "S"
        case .lapiz: return "P"
        case .marcador: return "M"
        case .goma: return "E"
        default: return ""
        }
    }

    static let porTecla: [String: Herramienta] = {
        var m: [String: Herramienta] = [:]
        for h in allCases where !h.tecla.isEmpty { m[h.tecla.lowercased()] = h }
        return m
    }()
}

/**
 * EL RAIL DE HERRAMIENTAS.
 *
 * Vertical y flotante, agrupado por funcion, con desplegables para las
 * variantes. Es la forma en que convergieron Figma, Miro y tldraw, y no por
 * moda: un rail vertical deja el ancho completo para el lienzo —que es donde se
 * trabaja— y los grupos hacen que la mano encuentre la herramienta sin leer.
 *
 * REGLA: el boton del grupo MUESTRA la ultima variante usada. Si elegiste el
 * marcador, el grupo queda con el icono del marcador — volver a el es un clic,
 * no dos. Un rail que siempre enseña el primero de cada grupo obliga a abrir el
 * desplegable cada vez para la herramienta que mas usas.
 */
final class RailHerramientas: NSView {

    /// Los grupos. El orden es el de la mano, no el del codigo.
    private static let grupos: [(id: String, items: [Herramienta])] = [
        ("puntero", [.seleccionar, .mano]),
        // NOTA y TEXTO viven en primer nivel, cada una con su boton: metidas en
        // un grupo, el icono de TEXTO no se veia nunca. Un grupo tiene sentido
        // para ocho formas que comparten gesto, no para tres herramientas que no
        // se parecen en nada y se usan a diario.
        ("nota", [.nota]),
        ("texto", [.texto]),
        ("formas", [.rect, .ellipse, .triangle, .diamond, .star, .pill, .hexagon, .arrow]),
        ("conector", [.conector, .conectorRecto, .conectorCurvo]),
        ("seccion", [.seccion]),
        ("tinta", [.lapiz, .marcador, .goma]),
        ("insertar", [.tabla, .imagen, .embed, .codigo]),
    ]

    /**
     * La paleta del lapiz. DOCE, no cincuenta y cinco.
     *
     * El canvas viejo ofrecia una cuadricula de 55 muestras, y esa es una
     * decision que nadie quiere tomar mientras dibuja. El estandar de Daniel es
     * paleta de RESTRICCION: una fila que se abarca de un vistazo se elige mas
     * rapido que una que hay que escanear.
     *
     * `nil` es la primera y es el DEFAULT: la tinta del tema, la unica que
     * sobrevive un cambio de claro a oscuro.
     */
    static let tintas: [String?] = [nil, "#8C27F1", "#dc2626", "#ea580c", "#d97706", "#16a34a",
                                    "#0d9488", "#2563eb", "#7c3aed", "#db2777", "#78716c", "#ffffff"]
    /**
     * LA ESCALERA DE GROSORES — px de MUNDO, como los guarda el trazo.
     *
     * ⚠️ NUEVE PELDAÑOS Y UNA SOLA ESCALERA, y esto arregla un fallo mudo.
     *
     * Eran cinco `[2, 4, 7, 12, 20]`, pero el dial de la tableta NO andaba por
     * ellos: sumaba de 0.5 en 0.5. Asi que girando la rueda el grosor pasaba
     * por 4.5, 5.0, 5.5... y `grosor == g` no se cumplia casi nunca — el panel
     * no marcaba NADA y parecia que la rueda no hacia efecto, cuando si lo
     * hacia. Daniel: *"al girar el dial yo esperaria ver moverse el grosor"*.
     *
     * Ahora hay UNA escalera y el dial anda por ella. El reparto no es lineal
     * sino aproximadamente geometrico, porque la diferencia que el ojo nota
     * entre 1 y 2 es la misma que entre 12 y 24: peldaños iguales en px darian
     * cuatro finos indistinguibles y un salto brutal al final.
     */
    static let grosores: [Double] = [1, 2, 3, 4, 6, 9, 13, 18, 26]

    var tema: Tema = .claro { didSet { repintar() } }
    var activa: Herramienta = .seleccionar {
        didSet {
            // Cambiar de herramienta por TECLADO tambien cierra el desplegable:
            // si no, la paleta del lapiz se queda abierta sobre el lienzo con la
            // herramienta ya cambiada, prometiendo algo que ya no aplica.
            if activa != oldValue { cerrarDesplegable() }
            repintar()
        }
    }
    /*
     * ⚠️ LA PALETA TIENE QUE REPINTARSE, no el panel que la contiene.
     *
     * Daniel: *"le estoy dando clic al grosor del marcador y tampoco
     * funciona"*. Sí funcionaba: el grosor cambiaba y el siguiente trazo salía
     * más grueso. Lo que NO cambiaba era la muestra marcada, porque se pedía el
     * repintado al PANEL —que no dibuja nada— y no a la paleta, que es quien
     * pinta el recuadro de "elegido".
     *
     * Un control que responde sin decir que respondió es, para la mano, un
     * control roto. Lo mide un ojo, no una prueba de estado.
     */
    var tinta: (color: String?, grosor: Double) = (nil, 4) {
        didSet {
            paleta?.actual = tinta
            paleta?.needsDisplay = true
        }
    }
    private weak var paleta: PaletaTinta?
    var alElegir: ((Herramienta) -> Void)?
    var alCambiarTinta: (((color: String?, grosor: Double)) -> Void)?
    /// El ajuste de la goma vive donde vive el de la tinta: en el rail, que es
    /// quien abre el panel. El lienzo lo empuja de vuelta cuando el dial lo
    /// mueve, para que el panel y la mano nunca digan cosas distintas.
    var goma = Goma() {
        didSet {
            gomaPanel?.actual = goma
            gomaPanel?.needsDisplay = true
        }
    }
    var alCambiarGoma: ((Goma) -> Void)?
    private weak var gomaPanel: PaletaGoma?

    private var ultimaDe: [String: Herramienta] = [:]
    private var botones: [(id: String, boton: BotonPlano)] = []
    private var desplegable: NSView?
    private var abierto: String?
    /// Que grupo tiene el panel abierto, si hay alguno. Lo necesita quien
    /// recoloca el cromo para volver a abrirlo donde toca.
    var grupoAbierto: String? { abierto }

    /**
     * Volver a colocar el desplegable tras mover el rail.
     *
     * ⚠️ Antes, quien recolocaba el cromo simplemente lo CERRABA — con el
     * argumento de que el panel se ancla al rail al abrirse y quedaria
     * huerfano si el rail se mueve. Cierto, pero la cura resulto peor: cambiar
     * el grosor escribe en la barra de estado, eso le cambia el ancho, y con
     * el aviso de ancho el cromo se recoloca entero. Es decir, girar el dial
     * CERRABA el panel del lapiz — justo el panel que se acababa de abrir para
     * ver moverse el grosor (Daniel: *"al contrario, cuando giro el dial
     * desaparece esta cosa"*).
     *
     * Reabrirlo conserva las dos cosas: ni se queda huerfano ni desaparece.
     */
    func recolocarDesplegable() {
        guard let id = abierto,
              let b = botones.first(where: { $0.id == id })?.boton,
              let items = Self.grupos.first(where: { $0.id == id })?.items else { return }
        abrirDesplegable(id, items, cerca: b)
    }
    private var globo: NSView?

    private let LADO: CGFloat = 48
    private let HUECO: CGFloat = 4

    /*
     * ⚠️ EL RAIL SE PINTABA AL REVES.
     *
     * AppKit apila desde el ORIGEN, y el origen de una vista no volteada esta
     * ABAJO a la izquierda. El rail salia con el cursor al fondo y la tabla
     * arriba: el orden exacto que el codigo declara, leido de abajo hacia
     * arriba.
     *
     * No falla nada y no hay error: la herramienta que mas se usa queda donde
     * la mano no la busca. Es el mismo tropiezo que ya se pago en el arbol de
     * lienzos el 20 ago, y volvio a aparecer en la superficie siguiente porque
     * el arreglo de alla fue un espaciador, no una regla.
     */
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        let alto = CGFloat(Self.grupos.count) * (48 + 4) + 16 + CGFloat(Self.grupos.count - 1) * 5
        super.init(frame: NSRect(x: 0, y: 0, width: 58, height: alto))
        montar()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func montar() {
        for (id, items) in Self.grupos {
            let b = BotonPlano(icono: items[0].icono, ancho: LADO, alto: LADO)
            b.identifier = NSUserInterfaceItemIdentifier(id)
            /*
             * ⚠️ CIERRE, NO target/action.
             *
             * `NSButton` con target/action solo dispara al terminar su bucle de
             * seguimiento del ratón, y ese bucle espera eventos del sistema. Un
             * `mouseDown` entregado a mano —el de la escena de verificación— lo
             * deja esperando y la acción NO ocurre: el botón se ve pulsado y no
             * hace nada.
             *
             * Con el cierre, el camino de la mano y el de la verificación son
             * EL MISMO. Si fueran distintos, la escena estaría probando una
             * ruta que ningún dedo recorre.
             */
            b.enfasis = .solido
            b.alPulsar = { [weak self, weak b] in if let b { self?.pulsar(b) } }
            b.alPulsarVariantes = { [weak self, weak b] in
                guard let self, let b, let id = b.identifier?.rawValue,
                      let items = Self.grupos.first(where: { $0.id == id })?.items else { return }
                self.abierto == id ? self.cerrarDesplegable() : self.abrirDesplegable(id, items, cerca: b)
            }
            addSubview(b)
            botones.append((id, b))
            // El menu contextual tambien abre las variantes: es la puerta que
            // un raton espera y no cuesta nada tenerla.
            if items.count > 1 { b.menu = NSMenu() }
        }
        repintar()
    }

    /// Coloca los botones y las lineas separadoras. Se llama al montar y cuando
    /// cambia el tamaño, que aqui es fijo pero el alto depende de los grupos.
    override func layout() {
        super.layout()
        var y: CGFloat = 8
        for (i, par) in botones.enumerated() {
            if i > 0 { y += 5 }
            par.boton.frame = NSRect(x: 5, y: y, width: LADO, height: LADO)
            y += LADO + HUECO
        }
    }

    override func draw(_ dirty: NSRect) {
        Estilo.pintarBisel(self, tema)
        super.draw(dirty)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        /*
         * SIN RÓTULO. El nombre de la herramienta vivió aquí un día (23-24 ago)
         * y Daniel lo retiró: el icono + el globo con su tecla ya lo dicen, y
         * el texto compite con los glifos. El nombre largo sigue en el globo.
         */
        /*
         * SEPARADOR GRABADO, no una raya.
         *
         * Una línea sola sobre metal se lee como suciedad. Un surco de verdad
         * son DOS: la sombra del corte y, justo debajo, el filo que la luz pega
         * al salir. Es el detalle más barato del sistema y el que más dice
         * "esto está mecanizado" en vez de "esto es un div con border-top".
         */
        let ancho = bounds.width - 22
        for (i, par) in botones.enumerated() where i > 0 {
            let y = par.boton.frame.minY - 3.5
            c.setFillColor(tema.bisel.borde.cgColor)
            c.fill(NSRect(x: 11, y: y, width: ancho, height: 1))
            c.setFillColor(tema.filoSurco.cgColor)
            c.fill(NSRect(x: 11, y: y + 1, width: ancho, height: 1))
        }
    }

    private func repintar() {
        Estilo.tarjeta(self, tema: tema)
        for (id, b) in botones {
            let items = Self.grupos.first { $0.id == id }!.items
            let enGrupo = items.contains(activa)
            let mostrada = enGrupo ? activa : (ultimaDe[id] ?? items[0])
            b.image = mostrada.icono
            b.tema = tema
            b.activo = enGrupo
            b.globo = mostrada.nombre + (items.count > 1 ? "  ·  \(items.count) variantes" : "")
            b.globoTecla = mostrada.tecla
            b.tieneVariantes = items.count > 1
        }
        needsDisplay = true
    }

    private func pulsar(_ b: NSButton) {
        guard let id = b.identifier?.rawValue,
              let items = Self.grupos.first(where: { $0.id == id })?.items else { return }
        let mostrada = items.contains(activa) ? activa : (ultimaDe[id] ?? items[0])
        // Si YA estas en esta herramienta, el clic ABRE sus variantes. Es la
        // convencion de Figma, y aqui hace falta de verdad: el punto de 3 px es
        // la unica pista de que hay mas, y una pista no puede ser la unica
        // puerta.
        if items.contains(activa) && items.count > 1 {
            /*
             * EL SEGUNDO CLIC CIERRA EL PANEL Y NO TOCA NADA MAS.
             *
             * Es un interruptor: el mismo boton que lo abre lo cierra, y al
             * cerrarse la herramienta sigue siendo la que era y el grosor el
             * que estaba (Daniel: *"si presiono otra vez el lapiz desaparezco
             * esto, pero obviamente me mantengo en el lapiz al grosor que
             * estaba"*). `cerrarDesplegable` solo quita la vista — no escribe
             * en `activa` ni en `tinta`, asi que no hay nada que preservar a
             * mano.
             *
             * ⚠️ ESTO YA SE CAMBIO UNA VEZ Y HUBO QUE DESHACERLO. Lei una
             * descripcion de lo que pasaba como si fuera una queja y lo deje
             * fijo abierto. Un panel que no se puede cerrar con el mismo gesto
             * que lo abrio no es "mas estable": es una puerta sin picaporte por
             * dentro.
             */
            abierto == id ? cerrarDesplegable() : abrirDesplegable(id, items, cerca: b)
        } else {
            elegir(id, mostrada)
        }
    }

    private func elegir(_ grupo: String, _ h: Herramienta) {
        ultimaDe[grupo] = h
        /*
         * CAMBIAR DE INSTRUMENTO DENTRO DEL PANEL LO DEJA ABIERTO.
         *
         * En los demás grupos elegir es el final del viaje: coges el hexágono y
         * te vas a dibujarlo. En el de tinta no, porque debajo hay AJUSTES: al
         * pasar de lápiz a goma el panel tiene que cambiar de paleta a tamaños
         * de goma, y cerrarse en ese momento obliga a volver a abrirlo con otro
         * clic para tocar lo que acabas de ir a buscar.
         */
        let reabrir = grupo == "tinta" && abierto == grupo
        cerrarDesplegable()
        activa = h
        alElegir?(h)
        if reabrir, let b = botones.first(where: { $0.id == grupo })?.boton,
           let items = Self.grupos.first(where: { $0.id == grupo })?.items {
            abrirDesplegable(grupo, items, cerca: b)
        }
    }

    /**
     * Abrir el desplegable de un grupo desde FUERA (un atajo de teclado).
     *
     * Existe porque los botones del lapiz fisico de la tableta mandan
     * ⌃P/⌃M/⌃E, y elegir la herramienta sin enseñar nada deja la mano sin
     * saber si el boton hizo algo: no hay puntero sobre el rail que resalte, y
     * el lapiz y el marcador comparten la misma casilla. Abrir su panel ES el
     * acuse de recibo.
     */
    func abrirGrupoDe(_ h: Herramienta) {
        guard let (id, items) = Self.grupos.first(where: { $0.items.contains(h) }),
              items.count > 1, let b = botones.first(where: { $0.0 == id })?.1 else { return }
        if abierto == id { return }
        abrirDesplegable(id, items, cerca: b)
    }

    func cerrarDesplegable() {
        desplegable?.removeFromSuperview()
        desplegable = nil
        abierto = nil
    }

    func abrirDesplegable(_ id: String, _ items: [Herramienta], cerca boton: NSView) {
        cerrarDesplegable()
        abierto = id
        let esTinta = id == "tinta"
        // La tinta pone sus tres herramientas EN FILA: debajo va su paleta, que
        // es ancha, y una columna de tres botones al lado de 200 px de paleta
        // deja el panel medio vacío y desalineado.
        let columnas = esTinta ? items.count : (items.count > 4 ? 2 : 1)
        let filas = (items.count + columnas - 1) / columnas
        let anchoPanel = CGFloat(columnas) * 41 + 10
        let altoExtra: CGFloat = esTinta ? (activa == .goma ? 96 : PaletaTinta.ALTO + 14) : 0
        let panel = Tarjeta(tema: tema, radio: 12)

        for (i, h) in items.enumerated() {
            let b = BotonPlano(icono: h.icono, ancho: 38, alto: 38)
            b.tema = tema
            b.enfasis = .solido
            b.activo = h == activa
            b.globo = h.nombre; b.globoTecla = h.tecla
            b.alPulsar = { [weak self] in self?.elegir(id, h) }
            let col = CGFloat(i % columnas), fila = CGFloat(i / columnas)
            b.frame = NSRect(x: 5 + col * 41, y: altoExtra + 5 + (CGFloat(filas) - 1 - fila) * 41,
                             width: 38, height: 38)
            panel.addSubview(b)
        }

        // AJUSTES DEL LAPIZ dentro de su propio desplegable: se eligen ANTES de
        // dibujar, que es cuando importan. Tenerlos solo en la barra contextual
        // obliga a trazar primero y corregir despues.
        if esTinta && activa == .goma {
            // LA GOMA NO TIENE COLOR. Enseñarle doce tintas a un instrumento que
            // quita es prometer algo que no hace; lo que sí tiene es TAMAÑO y
            // ALCANCE, y son las dos decisiones que se toman antes de barrer.
            // Mismo ancho que la del lapiz: son el mismo panel cambiando de
            // instrumento, y que la caja se encoja al pasar a la goma se lee
            // como un salto, no como un ajuste.
            let p = PaletaGoma(frame: NSRect(x: PaletaTinta.MARGEN, y: 6,
                                             width: PaletaTinta.ANCHO, height: 84))
            p.tema = tema
            p.actual = goma
            p.alElegir = { [weak self] g in
                self?.goma = g
                self?.alCambiarGoma?(g)
            }
            panel.addSubview(p)
            gomaPanel = p
        } else if esTinta {
            let p = PaletaTinta(frame: NSRect(x: PaletaTinta.MARGEN, y: 6,
                                              width: PaletaTinta.ANCHO, height: PaletaTinta.ALTO))
            p.tema = tema
            p.esMarcador = activa == .marcador
            p.actual = tinta
            p.alElegir = { [weak self] t in
                self?.tinta = t
                self?.alCambiarTinta?(t)
            }
            panel.addSubview(p)
            paleta = p
        }

        /*
         * ⚠️ EL RAIL ESTA VOLTEADO Y EL PADRE NO.
         *
         * Dentro del rail la Y crece hacia abajo; en la vista que contiene al
         * desplegable crece hacia arriba. Sumar la Y del botón tal cual colocaba
         * el panel más abajo cuanto más arriba estuviera su herramienta — un
         * desfase que crece con la distancia y que a simple vista parece "un
         * poco desalineado" en vez de un sistema de coordenadas equivocado.
         *
         * El borde superior del panel se alinea con el del botón, traduciendo.
         */
        let alto = CGFloat(filas) * 41 + 10 + altoExtra
        let arribaEnPadre = frame.maxY - boton.frame.minY
        panel.frame = NSRect(x: frame.maxX + 6,
                             y: max(8, arribaEnPadre - alto),
                             // ⚠️ El ancho SALE de lo que hay dentro. Estaba
                             // clavado en 208 con una paleta de 216 en x=10:
                             // 18 px de la fila de grosores se pintaban FUERA
                             // de la caja. Un numero magico al lado de otro
                             // numero magico se desincroniza en cuanto uno de
                             // los dos cambia, y esto ya cambio dos veces hoy.
                             // ⚠️ Y esto vale para la GOMA igual que para el
                             // lapiz. La primera version solo lo derivaba
                             // cuando NO era goma, asi que su panel volvia a
                             // medir lo que el rail: 200 px de paleta dentro de
                             // una caja de 133, con los dos ultimos discos y el
                             // boton "Todo" pintados fuera. Mismo fallo que
                             // acababa de arreglar, en la rama de al lado.
                             width: max(anchoPanel,
                                        esTinta ? PaletaTinta.ANCHO + PaletaTinta.MARGEN * 2
                                                : anchoPanel),
                             height: alto)
        superview?.addSubview(panel)
        desplegable = panel
    }
}

/**
 * LA PALETA DEL LAPIZ: la muestra, doce tintas y nueve grosores.
 *
 * ⚠️ ARRIBA VA UN TRAZO DE VERDAD, y no es adorno: es la unica forma de
 * responder "¿como va a salir?" sin dibujar y deshacer. Las casillas dicen QUE
 * color y QUE numero; el trazo dice como se SIENTE — con su punta afilada, su
 * panza y su cierre, que es justo lo que cambia entre un 4 y un 9 y lo que una
 * barra recta no puede enseñar.
 *
 * El marcador se pinta con SU transparencia real, porque un marcador opaco en
 * la muestra y translucido en el lienzo seria mentir en el sitio donde se
 * decide.
 */
final class PaletaTinta: NSView {
    var tema: Tema = .claro { didSet { needsDisplay = true } }
    var actual: (color: String?, grosor: Double) = (nil, 4) { didSet { needsDisplay = true } }
    /// El marcador enseña su trazo con la transparencia con la que pinta.
    var esMarcador = false { didSet { needsDisplay = true } }
    var alElegir: (((color: String?, grosor: Double)) -> Void)?

    override var isFlipped: Bool { true }

    private var celdas: [(r: NSRect, color: String?)] = []
    private var barras: [(r: NSRect, g: Double)] = []
    private var cuadroSV: NSRect = .zero
    private var tonoBarra: NSRect = .zero
    private var gotero: NSRect = .zero
    /// Qué superficie del espectro tiene agarrada la mano ahora mismo.
    private var zonaViva: Espectro.Zona?

    static let ANCHO: CGFloat = 216
    /*
     * ⚠️ LA GEOMETRÍA SE DECLARA UNA VEZ Y SE DERIVA.
     *
     * Estaba repartida en números sueltos dentro de `draw` (54, 108, 150, 186) y
     * copiada a mano en la escena que la pulsa. Con eso, mover una fila obliga a
     * acertar el mismo número en cinco sitios; el día que uno se queda atrás, el
     * clic de la prueba cae en la fila de al lado y la prueba sigue en verde
     * midiendo otra cosa. Ahora cada banda sale de la anterior.
     */
    static let Y_TINTAS: CGFloat = 54
    static var Y_ESPECTRO: CGFloat { 98 }
    static var Y_GROSORES: CGFloat { Y_ESPECTRO + Espectro.ALTO + 8 }
    static var Y_RECIENTES: CGFloat { Y_GROSORES + 36 }
    /// ⚠️ Incluye SIEMPRE el hueco de "tus colores", aunque no haya ninguno. Si
    /// la fila apareciera al guardar el primero, nacería fuera del panel: el
    /// desplegable mide su caja al abrirse y no vuelve a medirla.
    static var ALTO: CGFloat { Y_RECIENTES + Recientes.ALTO }
    /// Bajo qué nombre recuerda el lápiz los colores que se eligieron a mano.
    static let AMBITO = "lapiz"
    /// El margen entre la paleta y el filo de su caja, a los dos lados.
    static let MARGEN: CGFloat = 10

    private var tintaViva: NSColor {
        actual.color.flatMap { NSColor(hex: $0) } ?? tema.tinta
    }

    override func draw(_ dirty: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        celdas.removeAll(); barras.removeAll()

        // ── LA MUESTRA ───────────────────────────────────────────────────
        let cajaM = NSRect(x: 0, y: 0, width: bounds.width, height: 44)
        let caminoM = CGMutablePath()
        caminoM.addRoundedRectSeguro(in: cajaM, cornerWidth: 10, cornerHeight: 10)
        c.addPath(caminoM)
        c.setFillColor(tema.lienzo.cgColor)
        c.fillPath()
        c.addPath(caminoM)
        c.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        c.setLineWidth(1); c.strokePath()

        /*
         * El trazo se pinta en RODAJAS con el ancho variando, porque un solo
         * `stroke` de grosor constante no tiene punta ni panza — y la punta es
         * la mitad de lo que distingue un grosor de otro a simple vista.
         */
        let g = max(1, min(26, actual.grosor))
        let x0 = cajaM.minX + 16, x1 = cajaM.maxX - 16
        /*
         * ⚠️ LA DENSIDAD SALE DEL GROSOR, no es un numero fijo.
         *
         * Con 44 rodajas el trazo salia PUNTEADO en los grosores finos: dos
         * discos de 4 px separados 8 no se tocan. Y con un numero alto fijo,
         * los gruesos pintaban cien veces lo mismo. El paso tiene que ser una
         * fraccion del ANCHO —que es lo que decide cuanto solapan— y no de la
         * longitud, que es constante.
         */
        let pasos = max(60, Int((x1 - x0) / max(0.6, g * 0.22)))
        c.saveGState()
        /*
         * ⚠️ LA TRANSPARENCIA VA A LA CAPA, no a cada rodaja.
         *
         * Poniendo el alfa antes de pintar, cada disco se mezcla con el que
         * tiene debajo: donde solapan —que es en todas partes, porque para eso
         * solapan— el color se acumula y el marcador salia con textura de
         * ESCAMAS en vez de como una franja limpia. Una capa de transparencia
         * compone el trazo ENTERO primero y le aplica el alfa una sola vez al
         * final, que es como se comporta un marcador de verdad: pasar dos veces
         * por el mismo sitio en el MISMO trazo no oscurece.
         */
        if esMarcador { c.setAlpha(0.42); c.beginTransparencyLayer(auxiliaryInfo: nil) }
        c.setFillColor(tintaViva.cgColor)
        for k in 0..<pasos {
            let t = Double(k) / Double(pasos - 1)
            let x = x0 + (x1 - x0) * t
            // Seno para la panza y un afilado en los dos extremos: el trazo
            // nace fino, engorda y muere fino, como el de la mano.
            let perfil = sin(t * .pi)
            let w = max(1.2, g * (0.28 + 0.72 * pow(perfil, 0.45)))
            let y = cajaM.midY + sin(t * .pi * 1.6 - 0.5) * 7
            c.fillEllipse(in: NSRect(x: x - w / 2, y: y - w / 2, width: w, height: w))
        }
        if esMarcador { c.endTransparencyLayer() }
        c.restoreGState()
        // El numero, discreto, en la esquina: la muestra dice como se siente y
        // la cifra deja repetirlo mañana.
        // El numero va sobre su propia pastilla: encima del trazo grueso se
        // perdia, y un dato que hay que buscar no es un dato.
        let etq = String(format: g == g.rounded() ? "%.0f" : "%.1f", g)
        let anchoEtq = (etq as NSString).size(withAttributes: [.font: Estilo.mono(10, 700)]).width
        let past = NSRect(x: cajaM.maxX - anchoEtq - 16, y: cajaM.minY + 5,
                          width: anchoEtq + 10, height: 15)
        let cp = CGMutablePath()
        cp.addRoundedRectSeguro(in: past, cornerWidth: 5, cornerHeight: 5)
        c.addPath(cp)
        c.setFillColor(tema.rol("card").relleno.withAlphaComponent(0.9).cgColor)
        c.fillPath()
        (etq as NSString).draw(at: NSPoint(x: past.minX + 5, y: past.minY + 1),
                               withAttributes: [.font: Estilo.mono(10, 700),
                                                .foregroundColor: tema.pieTexto])

        // ── LAS TINTAS ───────────────────────────────────────────────────
        let lado: CGFloat = 20, hueco: CGFloat = 4, yTintas = Self.Y_TINTAS
        for (i, tinta) in RailHerramientas.tintas.enumerated() {
            let col = CGFloat(i % 6), fila = CGFloat(i / 6)
            let r = NSRect(x: col * (lado + hueco), y: yTintas + fila * (lado + hueco),
                           width: lado, height: lado)
            celdas.append((r, tinta))
            let camino = CGMutablePath()
            camino.addRoundedRectSeguro(in: r, cornerWidth: 6, cornerHeight: 6)
            c.addPath(camino)
            c.setFillColor((tinta.flatMap { NSColor(hex: $0) } ?? tema.tinta).cgColor)
            c.fillPath()
            let elegida = actual.color == tinta
            // La elegida lleva un anillo POR FUERA, no un borde mas gordo: un
            // borde de 2 come 2 px de color y en las tintas oscuras el cambio
            // no se ve. El anillo separado se ve en las doce por igual.
            if elegida {
                let anillo = CGMutablePath()
                anillo.addRoundedRectSeguro(in: r.insetBy(dx: -3, dy: -3), cornerWidth: 8, cornerHeight: 8)
                c.addPath(anillo)
                c.setStrokeColor(tema.acento.cgColor); c.setLineWidth(2); c.strokePath()
            }
            c.addPath(camino)
            c.setStrokeColor(tema.rol("card").trazo.color.cgColor)
            c.setLineWidth(1); c.strokePath()
            // La casilla del tema lleva una diagonal: es la unica que NO es un
            // color y sin marca se confunde con "negro".
            if tinta == nil {
                c.setStrokeColor(tema.lienzo.cgColor); c.setLineWidth(1.6)
                c.move(to: CGPoint(x: r.minX + 5, y: r.maxY - 5))
                c.addLine(to: CGPoint(x: r.maxX - 5, y: r.minY + 5))
                c.strokePath()
            }
        }

        // ── EL ESPECTRO: cualquier color, no solo los doce ───────────────
        //
        // El mecanismo NO vive aquí: es `Espectro`, y lo montan igual los cinco
        // paneles de color de la barra. Desde el 30 ago 2026 es un CUADRO
        // (saturación × brillo) más la barra de tono: las dos barras de antes
        // metían saturación y brillo en un solo eje, y con eso los tonos mudos
        // —un pizarra, un caqui— sencillamente no existían.
        let cajas = Espectro.cajas(x: 0, y: Self.Y_ESPECTRO, ancho: bounds.width)
        cuadroSV = cajas.cuadro; tonoBarra = cajas.tono
        Espectro.pintar(c, cuadro: cuadroSV, tono: tonoBarra, base: tintaViva,
                        hayColor: actual.color != nil, tema: tema)

        // ── LOS NUEVE GROSORES ───────────────────────────────────────────
        //
        // Cada peldaño es un DISCO de tamaño proporcional al de al lado, no una
        // barra igual para todos: la fila entera se lee como una rampa y se ve
        // de un vistazo en que punto estas y cuanto queda a cada lado. Ese es
        // el movimiento que el dial tiene que enseñar.
        let ns = RailHerramientas.grosores
        let y0: CGFloat = Self.Y_GROSORES
        let anchoB = bounds.width / CGFloat(ns.count)
        for (i, gr) in ns.enumerated() {
            let r = NSRect(x: CGFloat(i) * anchoB, y: y0, width: anchoB, height: 30)
            barras.append((r, gr))
            let elegido = abs(actual.grosor - gr) < 0.01
            if elegido {
                let camino = CGMutablePath()
                camino.addRoundedRectSeguro(in: r.insetBy(dx: 1.5, dy: 1), cornerWidth: 8, cornerHeight: 8)
                c.addPath(camino); c.setFillColor(tema.acento.cgColor); c.fillPath()
            }
            // Escalado, no a tamaño real: 26 px no caben en una celda de 30 y
            // los dos ultimos se verian del mismo diametro — el mismo fallo que
            // ya costo la version anterior de esta fila.
            // El disco crece con una raiz, no lineal: a tamaño real los cuatro
            // finos serian puntos identicos. Y el techo es 20 —no 18— porque
            // con 18 los dos ultimos peldaños se veian casi iguales, que es
            // justo lo que esta fila existe para distinguir.
            let d = max(3.5, min(20, 3 + pow(gr, 0.66) * 2.3))
            c.setFillColor(elegido ? NSColor.white.cgColor : tintaViva.cgColor)
            c.fillEllipse(in: NSRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d))
        }

        // ── TUS COLORES ──────────────────────────────────────────────────
        //
        // Las doce tintas son las de la casa. Estas son las que Daniel buscó
        // arrastrando por el arcoíris, y son justo las que se perdían al cerrar
        // el panel. Van ABAJO del todo a propósito: así ni una sola coordenada
        // de las de arriba se mueve.
        let yR: CGFloat = Self.Y_RECIENTES
        let guardados = Recientes.lista(Self.AMBITO)
        let rotulo = NSAttributedString(
            string: guardados.isEmpty ? "TUS COLORES · elige del cuadro" : "TUS COLORES",
            attributes: [.font: Estilo.fuente(9, 700), .foregroundColor: tema.pieTexto, .kern: 0.5])
        rotulo.draw(at: NSPoint(x: 1, y: yR + 2))

        /*
         * EL GOTERO, en la misma línea del rótulo porque ahí sobra sitio y es
         * donde pertenece: robar un color de la pantalla es la otra forma de
         * meter uno "tuyo". Dibujando es donde más falta hace — el color de una
         * miniatura, de una captura, de un lienzo de al lado.
         */
        gotero = NSRect(x: bounds.width - 26, y: yR - 2, width: 24, height: 18)
        let gp = CGMutablePath()
        gp.addRoundedRectSeguro(in: gotero, cornerWidth: 6, cornerHeight: 6)
        c.addPath(gp); c.setFillColor(tema.lienzo.cgColor); c.fillPath()
        c.addPath(gp); c.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        c.setLineWidth(1); c.strokePath()
        let gx = gotero.midX, gy = gotero.midY + 2, gr: CGFloat = 4.0
        let gota = CGMutablePath()
        gota.move(to: CGPoint(x: gx, y: gy - gr * 2.1))
        gota.addQuadCurve(to: CGPoint(x: gx + gr, y: gy), control: CGPoint(x: gx + gr * 0.9, y: gy - gr))
        gota.addArc(center: CGPoint(x: gx, y: gy), radius: gr, startAngle: 0, endAngle: .pi, clockwise: false)
        gota.addQuadCurve(to: CGPoint(x: gx, y: gy - gr * 2.1), control: CGPoint(x: gx - gr * 0.9, y: gy - gr))
        c.addPath(gota)
        c.setStrokeColor(tema.cuerpoTexto.cgColor); c.setLineWidth(1.3); c.strokePath()
        for (i, hx) in guardados.enumerated() {
            let r = NSRect(x: CGFloat(i) * (lado + hueco), y: yR + 16, width: lado, height: lado)
            celdas.append((r, hx))
            let camino = CGMutablePath()
            camino.addRoundedRectSeguro(in: r, cornerWidth: 6, cornerHeight: 6)
            c.addPath(camino)
            c.setFillColor((NSColor(hex: hx) ?? tema.tinta).cgColor)
            c.fillPath()
            if actual.color?.caseInsensitiveCompare(hx) == .orderedSame {
                let anillo = CGMutablePath()
                anillo.addRoundedRectSeguro(in: r.insetBy(dx: -3, dy: -3), cornerWidth: 8, cornerHeight: 8)
                c.addPath(anillo)
                c.setStrokeColor(tema.acento.cgColor); c.setLineWidth(2); c.strokePath()
            }
            c.addPath(camino)
            c.setStrokeColor(tema.rol("card").trazo.color.cgColor)
            c.setLineWidth(1); c.strokePath()
        }
    }

    private func elegirDeEspectro(_ p: NSPoint, _ z: Espectro.Zona) -> String {
        Espectro.hex(Espectro.color(p, zona: z, cuadro: cuadroSV, tono: tonoBarra,
                                    base: tintaViva, hayColor: actual.color != nil))
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if gotero.contains(p) { robarDeLaPantalla(); return }
        zonaViva = celdas.contains { $0.r.contains(p) }
            ? nil : Espectro.zona(p, cuadro: cuadroSV, tono: tonoBarra)
        tocar(p)
    }

    /// Roba el color de cualquier punto de la pantalla con la lupa del sistema.
    /// Se guarda en "tus colores": cuesta el mismo gesto que buscarlo a mano y
    /// perderlo dolería igual.
    func robarDeLaPantalla() {
        NSColorSampler().show { [weak self] c in
            guard let self, let c else { return }
            let h = Espectro.hex(c)
            self.actual = (h, self.actual.grosor)
            self.alElegir?((h, self.actual.grosor))
            Recientes.recordar(h, en: Self.AMBITO)
            self.needsDisplay = true
        }
    }

    override func mouseUp(with e: NSEvent) {
        guard zonaViva != nil else { return }
        zonaViva = nil
        // Se guarda al SOLTAR: buscar un color pasa por cuarenta que no quisiste.
        if let c = actual.color { Recientes.recordar(c, en: Self.AMBITO); needsDisplay = true }
    }
    /// Arrastrar por las barras cambia el color EN VIVO: elegir un color es
    /// buscarlo, no acertarlo a la primera.
    override func mouseDragged(with e: NSEvent) {
        guard let z = zonaViva else { return }
        alElegir?((elegirDeEspectro(convert(e.locationInWindow, from: nil), z), actual.grosor))
    }

    private func tocar(_ p: NSPoint) {
        if let c = celdas.first(where: { $0.r.contains(p) }) { alElegir?((c.color, actual.grosor)); return }
        if let z = zonaViva { alElegir?((elegirDeEspectro(p, z), actual.grosor)); return }
        if let b = barras.first(where: { $0.r.contains(p) }) { alElegir?((actual.color, b.g)) }
    }
}

/**
 * EL PANEL DE LA GOMA: cinco tamaños y dos alcances.
 *
 * Las dos únicas decisiones que una goma admite, y las dos se toman ANTES de
 * barrer —que es cuando importan— sin salir del sitio donde ya estaba la mano.
 *
 * El tamaño se enseña como un DISCO, no como una barra: la goma actúa en área,
 * y una barra pediría traducir "grueso" a "redondo" en la cabeza cada vez. Los
 * discos van escalados y no a tamaño real, porque 80 px de mundo no caben en una
 * celda de 34 y los dos últimos se verían idénticos — el mismo fallo que ya
 * costó la fila de grosores del lápiz.
 */
final class PaletaGoma: NSView {
    var tema: Tema = .claro { didSet { refrescar(); needsDisplay = true } }
    var actual = Goma() { didSet { refrescar(); needsDisplay = true } }
    var alElegir: ((Goma) -> Void)?

    override var isFlipped: Bool { true }

    private var discos: [(r: NSRect, g: Double)] = []
    private var botones: [(b: BotonPlano, a: Goma.Alcance)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Los dos alcances son BOTONES DE VERDAD y no rectángulos pintados a
        // mano: así heredan el cromo de la casa —el bisel, el hover, el globo,
        // el énfasis sólido de "esto es un modo"— en vez de imitarlo y quedarse
        // atrás en cuanto el estilo cambie en un sitio y no en el otro.
        let hueco: CGFloat = 4
        let ancho = (frame.width - hueco) / 2
        for (i, a) in Goma.Alcance.allCases.enumerated() {
            let b = BotonPlano(icono: nil, titulo: a.nombre, ancho: ancho, alto: 30)
            b.frame = NSRect(x: CGFloat(i) * (ancho + hueco), y: 46, width: ancho, height: 30)
            b.enfasis = .solido
            b.globo = a.ayuda
            b.alPulsar = { [weak self] in
                guard let s = self else { return }
                var g = s.actual; g.alcance = a; s.alElegir?(g)
            }
            addSubview(b)
            botones.append((b, a))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// El botón marcado y el tema siguen al estado, siempre desde un solo sitio.
    private func refrescar() {
        for (b, a) in botones {
            b.tema = tema
            b.activo = actual.alcance == a
        }
    }

    override func draw(_ dirty: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        discos.removeAll()

        let n = Goma.grosores.count
        let hueco: CGFloat = 4
        let lado = (bounds.width - CGFloat(n - 1) * hueco) / CGFloat(n)
        for (i, g) in Goma.grosores.enumerated() {
            let celda = NSRect(x: CGFloat(i) * (lado + hueco), y: 0, width: lado, height: 38)
            discos.append((celda, g))
            let elegido = actual.grosor == g
            if elegido {
                let camino = CGMutablePath()
                camino.addRoundedRectSeguro(in: celda, cornerWidth: 9, cornerHeight: 9)
                c.addPath(camino); c.setFillColor(tema.acento.cgColor); c.fillPath()
            }
            // Escalado a la celda: del más fino al más gordo hay un factor 10, y
            // sin comprimirlo el primero es invisible o el último no cabe.
            let d = 6 + (g - Goma.grosores[0]) / (Goma.grosores[n - 1] - Goma.grosores[0]) * 18
            c.setFillColor((elegido ? NSColor.white : tema.cuerpoTexto).withAlphaComponent(elegido ? 1 : 0.75).cgColor)
            c.fillEllipse(in: NSRect(x: celda.midX - d / 2, y: celda.midY - d / 2, width: d, height: d))
        }

    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let d = discos.first(where: { $0.r.contains(p) }) {
            var g = actual; g.grosor = d.g; alElegir?(g)
        }
    }
}
