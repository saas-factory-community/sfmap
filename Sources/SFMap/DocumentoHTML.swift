import AppKit
import WebKit
import CryptoKit

/// Un artefacto local, con su fragmento, sin copiarlo ni levantar un servidor.
/// La carpeta del artefacto es el límite de lectura de WebKit, no todo el repo.
struct ArtefactoHTML: Equatable {
    let archivo: URL
    let destino: URL
    var carpeta: URL { archivo.deletingLastPathComponent() }

    static func esHTML(_ ruta: String) -> Bool {
        let nombre = ruta.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ruta
        return ["html", "htm"].contains(URL(fileURLWithPath: nombre).pathExtension.lowercased())
    }

    static func resolver(_ ruta: String, repo: URL = Enlace.repo) -> ArtefactoHTML? {
        let partes = ruta.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let nombre = partes.first.map(String.init), !nombre.isEmpty,
              !nombre.hasPrefix("/"), !nombre.contains("://"),
              !nombre.split(separator: "/").contains(".."), esHTML(nombre) else { return nil }
        let raiz = repo.resolvingSymlinksInPath().standardizedFileURL
        let archivo = raiz.appendingPathComponent(nombre).resolvingSymlinksInPath().standardizedFileURL
        guard archivo.path.hasPrefix(raiz.path + "/"),
              FileManager.default.isReadableFile(atPath: archivo.path) else { return nil }
        var componentes = URLComponents(url: archivo, resolvingAgainstBaseURL: false)!
        if partes.count == 2 { componentes.fragment = String(partes[1]) }
        guard let destino = componentes.url else { return nil }
        return ArtefactoHTML(archivo: archivo, destino: destino)
    }
}

/// Un único WebKit, creado al abrir HTML. Es hermano del lienzo, nunca se escala
/// con su cámara. Markdown conserva su renderer AppKit y su arranque habitual.
final class DocumentoHTML: NSView, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    private(set) var artefacto: ArtefactoHTML?
    private(set) var estado = "cerrado"
    private(set) var errorCarga: String?
    private(set) var sha256 = ""
    private(set) var cargaMS: Double?
    var alCambiar: (() -> Void)?
    var alAbrirLiga: ((String) -> Void)?
    private var inicio = Date()
    private var leyendo = false
    private var generacion = 0
    private var ultimaLectura: [String: Any] = [:]
    private var observacionTitulo: NSKeyValueObservation?

    override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        web = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.underPageBackgroundColor = NSColor(white: 0.055, alpha: 1)
        web.setAccessibilityLabel("Documento HTML interactivo")
        observacionTitulo = web.observe(\.title, options: [.new]) { [weak self] _, _ in self?.alCambiar?() }
        addSubview(web)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); web.frame = bounds }

    func abrir(_ a: ArtefactoHTML, recargar: Bool = false) {
        if a == artefacto && estado == "listo" && !recargar { return }
        generacion += 1
        ultimaLectura = [:]
        artefacto = a
        errorCarga = nil
        estado = "cargando"
        cargaMS = nil
        inicio = Date()
        if let data = try? Data(contentsOf: a.archivo) {
            sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        web.loadFileURL(a.destino, allowingReadAccessTo: a.carpeta)
        alCambiar?()
    }

    func recargar() { if let a = artefacto { abrir(a, recargar: true) } }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        estado = "listo"
        cargaMS = Date().timeIntervalSince(inicio) * 1000
        traza("HTML listo · \(artefacto?.archivo.lastPathComponent ?? "") · \(Int(cargaMS ?? 0)) ms")
        alCambiar?()
    }

    private func fallo(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        estado = "error"; errorCarga = error.localizedDescription
        traza("HTML fallo · \(error.localizedDescription)")
        alCambiar?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fallo(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fallo(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        estado = "error"; errorCarga = "La vista se detuvo. Pulsa Recargar para recuperarla."
        alCambiar?()
    }

    /// Las fuentes externas se abren solo por un clic; no sustituyen el atlas.
    /// No se ofrece a los HTML una API de escritura o de ejecución de comandos.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = action.request.url else { decisionHandler(.cancel); return }
        if u.isFileURL, let a = artefacto,
           u.resolvingSymlinksInPath().standardizedFileURL.path == a.archivo.path {
            decisionHandler(.allow); return
        }
        if action.navigationType == .linkActivated {
            if u.isFileURL {
                let raiz = Enlace.repo.resolvingSymlinksInPath().path + "/"
                let destino = u.resolvingSymlinksInPath().standardizedFileURL
                if destino.path.hasPrefix(raiz), ["md", "html", "htm"].contains(destino.pathExtension.lowercased()) {
                    let relativo = String(destino.path.dropFirst(raiz.count))
                    alAbrirLiga?("doc:" + relativo + (u.fragment.map { "#" + $0 } ?? ""))
                }
            } else if ["https", "http"].contains(u.scheme?.lowercased() ?? "") {
                alAbrirLiga?(u.absoluteString)
            }
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    /// Estado básico de lectura para Levy: el mismo archivo y la sección real.
    /// El texto es del documento/selección, no se presenta como captura visual.
    func leerEstado(_ completado: @escaping ([String: Any]) -> Void) {
        guard !leyendo else { return }
        var base: [String: Any] = ["estado": estado, "archivo": artefacto?.archivo.path ?? "",
                                   "sha256": sha256, "url": web.url?.absoluteString ?? ""]
        if let cargaMS { base["carga_ms"] = Int(cargaMS) }
        if let errorCarga { base["error"] = errorCarga }
        guard estado == "listo" else { completado(base); return }
        leyendo = true
        let version = generacion
        web.evaluateJavaScript(Self.lecturaJS) { [weak self] valor, error in
            guard let self else { return }
            self.leyendo = false
            guard version == self.generacion else { return }
            if let lectura = valor as? [String: Any] { self.ultimaLectura = lectura }
            base["vista"] = self.ultimaLectura
            if let error { base["error_lectura"] = error.localizedDescription }
            completado(base)
        }
    }

    static let lecturaJS = """
    (() => {
      const dialogos = [...document.querySelectorAll('dialog[open], [role="dialog"][aria-modal="true"]')]
        .filter(x => x.getClientRects().length && getComputedStyle(x).visibility !== 'hidden');
      const lectura = dialogos.at(-1) || document.querySelector('main .panel:not([hidden])') || document.querySelector('main') || document.body;
      return {
      titulo: document.title, url: location.href, fragmento: location.hash,
      listo: document.readyState,
      viewport: {ancho: innerWidth, alto: innerHeight},
      scroll: {x: Math.round(scrollX), y: Math.round(scrollY)},
      seleccion: String(getSelection()).slice(0, 4000),
      paneles: [...document.querySelectorAll('main .panel:not([hidden])')].map(x => x.id),
      dialogos: dialogos.map(x => ({id: x.id, titulo: x.getAttribute('aria-label') || x.querySelector('h1,h2,h3')?.innerText || ''})),
      controles: [...document.querySelectorAll('[aria-current="page"], [aria-pressed="true"], button.active')]
        .filter(x => x.getClientRects().length).map(x => x.innerText).slice(0, 30),
      texto: lectura.innerText.slice(0, 20000),
      imagenes: [...lectura.querySelectorAll('img')].map(x => ({alt: x.alt, cargada: x.complete && x.naturalWidth > 0})).slice(0, 40)
    }; })()
    """
}
