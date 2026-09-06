import Foundation

/**
 * A DONDE LLEVA UN ELEMENTO — el enrutador de destinos del lienzo.
 *
 * ⚠️ POR QUE NO HAY CAMPOS NUEVOS. El elemento ya tenía `link`, ya se pintaba
 * su marca y ⌘+clic ya lo abría. Meter `doc:` y `page:` como CAMPOS aparte
 * habría dado tres conceptos donde el documento ya tenía uno, y el estándar es
 * explícito: *"la variedad sin información se poda"*. Aquí la variedad SÍ lleva
 * información —un documento no es una página web ni otro lienzo— y por eso lo
 * que cambia es el ESQUEMA de la liga y la MARCA que se pinta, no el modelo.
 *
 * Los cuatro destinos:
 *
 *   doc:ruta/relativa/al/repo.md   → el panel nativo de markdown
 *   page:<page_id>                 → navega a otro lienzo (el grafo de grafos)
 *   http(s)://…youtube|youtu.be|.mp4|sfcast  → vídeo (marca de reproducción)
 *   http(s)://…                    → el navegador
 *
 * El esquema `doc:` guarda ruta RELATIVA al repo a propósito: una ruta absoluta
 * viaja mal entre el MacBook y el Mac Mini, y este documento se sincroniza.
 */
enum Enlace {
    enum Destino: Equatable {
        case documento(String)   // ruta relativa al repo
        case pagina(String)      // page_id
        case video(URL)
        case web(URL)
        /// La APP dueña de lo que el widget enseña. Enmienda del 25 ago: el
        /// panel es espejo, y **navegar a la cabina correcta ES mirar mejor**.
        /// Daniel mira el calendario aquí y lo EDITA en sfcal; que el widget lo
        /// lleve allá de un clic no le da capacidad de escritura al panel, le
        /// quita el paso de buscar la app en el Dock.
        case app(String, String?)   // ("sfcal", "monkMode") · la vista es opcional
    }

    /// Dónde vive cada app dueña. Por RUTA y no por bundle id porque las de
    /// Daniel no están en el App Store y `openApplication(withBundleIdentifier:)`
    /// depende de que LaunchServices las tenga indexadas — cosa que un rebuild
    /// rompe en silencio (la misma familia del gotcha de TCC con la firma).
    static func rutaApp(_ crudo: String) -> URL? {
        // ⚠️ Se ignora cualquier sufijo. Un lienzo puede traer un `app:` con una
        // cola que ESTA versión no conoce todavía (los lienzos viajan por la
        // nube y la app se instala aparte). Sin esto, un sufijo nuevo hacía que
        // el nombre no casara y el doble clic NO ABRÍA NADA, en silencio.
        let nombre = crudo.split(separator: "?").first.map(String.init)?.lowercased() ?? crudo
        let fm = FileManager.default
        let casa = fm.homeDirectoryForCurrentUser
        let candidatas: [URL] = switch nombre {
            case "sfcal": [casa.appendingPathComponent("Applications/sfcal.app"),
                           casa.appendingPathComponent("Developer/software/sfcal/dist/sfcal.app"),
                           URL(fileURLWithPath: "/Applications/sfcal.app")]
            case "todoist": [URL(fileURLWithPath: "/Applications/Todoist.app"),
                             casa.appendingPathComponent("Applications/Todoist.app")]
            default: []
        }
        return candidatas.first { fm.fileExists(atPath: $0.path) }
    }

    /// Si la app no está instalada, a dónde ir. Todoist tiene web; sfcal no
    /// —es de Daniel y solo vive en su máquina—, así que ahí se falla honesto
    /// en vez de abrir una pestaña que no existe.
    static func webDeApp(_ nombre: String) -> URL? {
        nombre == "todoist" ? URL(string: "https://app.todoist.com/app/today") : nil
    }

    /// La raíz del repo: de ahí cuelgan las rutas de `doc:`.
    ///
    /// Se busca por MARCA en disco (`CLAUDE.md` + `.claude/`) subiendo desde
    /// varios puntos de partida, y no por una ruta escrita a mano, porque la
    /// app corre desde `~/Applications` en producción y desde `.build` en
    /// desarrollo: una constante habría funcionado en exactamente uno de los
    /// dos sitios. Se puede forzar con `SFMAP_REPO` (lo usan las pruebas).
    static var repo: URL = {
        if let s = ProcessInfo.processInfo.environment["SFMAP_REPO"] {
            return URL(fileURLWithPath: s)
        }
        let fm = FileManager.default
        var candidatos = [URL(fileURLWithPath: #filePath)]
        candidatos.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Developer/business-os"))
        for c in candidatos {
            var u = c
            for _ in 0..<12 {
                if fm.fileExists(atPath: u.appendingPathComponent("CLAUDE.md").path),
                   fm.fileExists(atPath: u.appendingPathComponent(".claude").path) { return u }
                let arriba = u.deletingLastPathComponent()
                if arriba.path == u.path { break }
                u = arriba
            }
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Developer/business-os")
    }()

    /// Extensiones y anfitriones que hacen de una liga un VÍDEO.
    static func esVideo(_ s: String) -> Bool {
        let b = s.lowercased()
        if b.hasSuffix(".mp4") || b.hasSuffix(".mov") || b.hasSuffix(".webm") { return true }
        for a in ["youtube.com/watch", "youtu.be/", "youtube.com/embed",
                  "sfcast", "/cast/", "vimeo.com/"] where b.contains(a) { return true }
        return false
    }

    static func leer(_ liga: String?) -> Destino? {
        guard var s = liga?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        if s.lowercased().hasPrefix("doc:") {
            var ruta = String(s.dropFirst(4))
            while ruta.hasPrefix("/") { ruta.removeFirst() }
            // `..` fuera: una liga del documento no navega el disco hacia arriba.
            guard !ruta.isEmpty, !ruta.split(separator: "/").contains("..") else { return nil }
            return .documento(ruta)
        }
        if s.lowercased().hasPrefix("app:") {
            // `app:sfcal?vista=monkMode` — el sufijo dice A QUÉ VISTA, no solo a
            // qué app. Sin él sigue funcionando: abre la app y ya.
            var n = String(s.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            var vista: String?
            if let q = n.firstIndex(of: "?") {
                let cola = String(n[n.index(after: q)...])
                n = String(n[..<q])
                if cola.hasPrefix("vista=") { vista = String(cola.dropFirst(6)) }
            }
            n = n.lowercased()
            return n.isEmpty ? nil : .app(n, vista)
        }
        if s.lowercased().hasPrefix("page:") {
            let id = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : .pagina(id)
        }
        if s.lowercased().hasPrefix("video:") { s = String(s.dropFirst(6)) }
        // Sin esquema se asume https: pegar "saasfactory.so" es lo normal, y
        // una URL sin esquema la rechaza URLSession en silencio (el mismo fallo
        // que tuvieron las imágenes con ruta local el 24 ago).
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s) else { return nil }
        return esVideo(s) ? .video(u) : .web(u)
    }

    /// La ruta ABSOLUTA de un `doc:`, ya resuelta contra la raíz del repo.
    static func rutaDoc(_ relativa: String) -> URL { repo.appendingPathComponent(relativa) }

    /// Qué marca se pinta en la esquina. El ojo tiene que saber a dónde va a ir
    /// ANTES de pulsar: una marca única para cuatro destinos es una promesa
    /// vaga, y una promesa vaga en un mapa vivo se deja de pulsar.
    enum Marca { case documento, pagina, video, web, app }

    static func marca(_ liga: String?) -> Marca? {
        switch leer(liga) {
        case .documento: .documento
        case .pagina:    .pagina
        case .video:     .video
        case .web:       .web
        case .app:       .app
        case nil:        nil
        }
    }
}
