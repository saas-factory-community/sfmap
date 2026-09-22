import AppKit
import WebKit
import CryptoKit

/// El HTML es un objeto del documento. Su viewport lógico no cambia cuando
/// cambia la cámara: AppKit escala la vista completa, sin remaquetar la web.
final class EmbedHTML: NSView {
    static let anchoLogico: CGFloat = 1440
    static let cabecera: CGFloat = 48
    let documento = DocumentoHTML(frame: .zero)
    private let titulo = NSTextField(labelWithString: "")
    private let ayuda = NSTextField(labelWithString: "Doble clic para interactuar")
    private(set) var elementoID: String?
    private(set) var ruta: String?
    private(set) var interactivo = false
    var tema: Tema = .oscuro { didSet { if oldValue.nombre != tema.nombre { needsDisplay = true } } }
    var alPintar: (() -> Void)?
    var alAbrirLiga: ((String) -> Void)?
    private let modo = NSButton(title: "Editar mapa", target: nil, action: nil)
    private(set) var maquetaciones = 0
    private var sacandoFoto = false
    private var fotografiada: String?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        titulo.font = Estilo.fuente(18, 700)
        titulo.textColor = .white
        titulo.lineBreakMode = .byTruncatingTail
        ayuda.font = Estilo.fuente(13, 500)
        ayuda.textColor = NSColor(white: 0.68, alpha: 1)
        addSubview(documento); addSubview(titulo); addSubview(ayuda)
        modo.target = self; modo.action = #selector(alternarModo)
        modo.bezelStyle = .rounded; addSubview(modo)
        documento.alAbrirLiga = { [weak self] s in self?.alAbrirLiga?(s) }
        documento.alCambiar = { [weak self] in
            guard let self else { return }
            self.titulo.stringValue = self.documento.web.title ?? "HTML interactivo"
            if let error = self.documento.errorCarga { self.ayuda.stringValue = error }
            if self.documento.estado == "listo" { self.fotografiar() }
        }
        setAccessibilityLabel("HTML dentro del lienzo")
    }
    required init?(coder: NSCoder) { nil }

    static func ruta(_ e: Elemento) -> String? {
        guard e.tipo == "embed", let u = e.crudo["url"]?.s, u.hasPrefix("doc:") else { return nil }
        let r = String(u.dropFirst(4))
        return ArtefactoHTML.esHTML(r) ? r : nil
    }

    static func marco(_ caja: CGRect, camara: Camara, viewport: CGSize) -> CGRect {
        CGRect(x: (caja.minX - camara.x) * camara.zoom + viewport.width / 2,
               y: (caja.minY - camara.y) * camara.zoom + viewport.height / 2,
               width: caja.width * camara.zoom, height: caja.height * camara.zoom)
    }

    func colocar(_ e: Elemento, camara: Camara, viewport: CGSize) {
        guard let ruta = Self.ruta(e) else { isHidden = true; return }
        let cambio = elementoID != e.id || self.ruta != ruta
        elementoID = e.id
        self.ruta = ruta
        let nuevo = Self.marco(e.caja, camara: camara, viewport: viewport)
        let logico = CGSize(width: Self.anchoLogico,
                            height: Self.anchoLogico * e.alto / max(1, e.ancho))
        let cambiaEscala = frame.size != nuevo.size
        let cambiaContenido = bounds.size != logico
        // Pan: solo desplazar la capa. No invalidar la maqueta ni el viewport web.
        if cambiaEscala {
            frame = nuevo
            bounds = CGRect(origin: .zero, size: logico)
        } else if frame.origin != nuevo.origin {
            setFrameOrigin(nuevo.origin)
        }
        if cambiaContenido { bounds = CGRect(origin: .zero, size: logico) }
        isHidden = !nuevo.intersects(CGRect(origin: .zero, size: viewport))
        if cambio || cambiaContenido {
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        if cambio {
            ponerModoTrabajo(true)
            fotografiada = nil
            titulo.stringValue = e.crudo["name"]?.s ?? "HTML interactivo"
            if let a = ArtefactoHTML.resolver(ruta) { documento.abrir(a) }
            else { ayuda.stringValue = "No se encontró el HTML local" }
        }
    }

    override func layout() {
        super.layout()
        maquetaciones += 1
        titulo.frame = CGRect(x: 18, y: 13, width: bounds.width - 580, height: 24)
        ayuda.frame = CGRect(x: bounds.width - 550, y: 15, width: 330, height: 20)
        modo.frame = CGRect(x: bounds.width - 195, y: 9, width: 175, height: 30)
        documento.frame = CGRect(x: 1, y: Self.cabecera, width: bounds.width - 2,
                                 height: max(0, bounds.height - Self.cabecera - 1))
        documento.layoutSubtreeIfNeeded()
    }

    override func draw(_ dirty: NSRect) {
        Estilo.pintarBisel(self, tema, radio: 0)
    }

    /// El primer clic selecciona/mueve el objeto. Solo tras entrar, los eventos
    /// pertenecen al HTML. El marco sigue disponible para moverlo en el lienzo.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if modo.frame.contains(local) { return modo }
        guard interactivo else { return nil }
        guard local.y > Self.cabecera, local.x > 8, local.x < bounds.width - 8,
              local.y < bounds.height - 8 else { return nil }
        return super.hitTest(point)
    }

    func activar() {
        guard !isHidden else { return }
        ponerModoTrabajo(true)
        window?.makeFirstResponder(documento.web)
    }

    func desactivar() {
        ponerModoTrabajo(false)
    }

    func ponerModoTrabajo(_ activo: Bool) {
        interactivo = activo
        modo.title = activo ? "Editar mapa" : "Trabajar"
        ayuda.stringValue = activo ? "Trabajar · clic directo" : "Editar · mueve el objeto"
    }

    @objc private func alternarModo() {
        ponerModoTrabajo(!interactivo)
        if !interactivo { window?.makeFirstResponder(superview) }
    }

    func escapar(_ alSalir: @escaping () -> Void) {
        documento.web.evaluateJavaScript("(() => {const d=[...document.querySelectorAll('dialog[open]')].at(-1);if(d){d.close();return true;}return false;})()") { [weak self] cerro, _ in
            if (cerro as? Bool) != true { self?.desactivar(); alSalir() }
        }
    }

    /// Vista previa local para el export/minimapa y otras piezas no activas.
    /// No reescribe el HTML ni el JSON del documento al capturar.
    func fotografiar() {
        guard !sacandoFoto, let ruta, documento.estado == "listo",
              fotografiada != documento.sha256, documento.web.bounds.width > 0 else { return }
        sacandoFoto = true
        let hash = documento.sha256
        let c = WKSnapshotConfiguration()
        c.snapshotWidth = NSNumber(value: Double(Self.anchoLogico))
        documento.web.takeSnapshot(with: c) { [weak self] imagen, _ in
            guard let self else { return }
            self.sacandoFoto = false
            guard self.ruta == ruta, let imagen else { return }
            PreviewHTML.guardar(imagen, ruta: ruta)
            self.fotografiada = hash
            self.alPintar?()
        }
    }
}

enum PreviewHTML {
    private static var imagenes: [String: NSImage] = [:]
    static func archivo(_ ruta: String) -> URL {
        let key = SHA256.hash(data: Data(ruta.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.saasfactory.sfmap/html/\(key).png")
    }
    static func imagen(_ ruta: String) -> NSImage? {
        if let i = imagenes[ruta] { return i }
        if let i = NSImage(contentsOf: archivo(ruta)) { imagenes[ruta] = i; return i }
        return nil
    }
    static func guardar(_ imagen: NSImage, ruta: String) {
        imagenes[ruta] = imagen
        let u = archivo(ruta)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let tiff = imagen.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: u, options: .atomic) }
    }
}
