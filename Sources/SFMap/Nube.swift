import Foundation

/// Lectura y escritura contra la MISMA tabla `draw` que el lienzo web.
///
/// Va directo a Supabase, no al servidor de Next: sfmap tiene que abrir aunque
/// el `npm run dev` no esté levantado. Una app de escritorio que depende de que
/// otro proceso esté corriendo no es una app, es una pestaña con marco.
///
/// La credencial se lee de `~/.sfmap/env` y NUNCA se copia dentro del
/// bundle: una llave horneada en un .app viaja a donde viaje el .app.
/// Traza a stderr. Existe porque la primera vez que la carga falló, la app no
/// dijo NADA: ni error en pantalla ni línea en consola. Un fallo silencioso
/// obliga a adivinar, y adivinar es lo que este proyecto lleva todo el día
/// demostrando que no funciona.
func traza(_ s: String) {
    let linea = "[sfmap] \(s)\n"
    FileHandle.standardError.write(linea.data(using: .utf8)!)
    /*
     * ⚠️ Y AL DISCO, o el sensor no existe.
     *
     * Una app con interfaz lanzada desde el Dock no tiene una terminal donde
     * escupir su stderr: se lo traga `launchd`. Asi que la traza que existia
     * "para que un fallo no fuera silencioso" era exactamente igual de
     * silenciosa que no tenerla — el fallo que este proyecto lleva persiguiendo
     * todo el dia, cometido por el propio sensor.
     */
    if let d = linea.data(using: .utf8) {
        let ruta = "/tmp/sfmap-run.log"
        if let fh = FileHandle(forWritingAtPath: ruta) {
            fh.seekToEndOfFile(); fh.write(d); try? fh.close()
        } else {
            try? d.write(to: URL(fileURLWithPath: ruta))
        }
    }
}

enum Nube {
    struct Config { var url: String; var key: String; var owner: String }

    static let esquemaV4 = 4

    /*
     * ⚠️ EL MISMO FILTRO QUE LA WEB, y no es opcional.
     *
     * `draw` tiene 129 filas; el lienzo web enseña 24. La diferencia son
     * páginas de otro dueño y páginas marcadas como borradas — que siguen en
     * la tabla porque el borrado es lógico, no físico.
     *
     * Sin filtrar, sfmap listaba las 129 y decía "101 SIN CARPETA": basura de
     * pruebas y papelera presentadas como si fueran lienzos de Daniel. Un
     * listado que enseña de más es peor que uno que enseña de menos: el de
     * menos se nota, el de más se confunde con trabajo real.
     */
    static var dueno: String { config?.owner ?? "" }
    static var filtroDueno: String { "user_id=eq.\(dueno)&is_deleted=eq.false" }

    /**
     * ⚠️ SOLO LECTURA. El candado que separa una verificación de un accidente.
     *
     * Las escenas de verificación conducen la app DE VERDAD: crean figuras,
     * arrastran, escriben. Y la app guarda sola 600 ms después de cada cambio.
     * Sin este candado, correr una escena escribe en la página real de Daniel —
     * y una escena que empieza con el lienzo en blanco la deja EN BLANCO.
     *
     * No es hipotético: el 20 ago 2026 la primera corrida de la escena `rail`
     * dejó un rectángulo huérfano en "La Máquina en Frío" y subió la versión a
     * 99. Se reparó, pero la lección es la de siempre — el arreglo no es
     * acordarse, es que el camino no exista.
     */
    static var soloLectura = CommandLine.arguments.contains("--escena")
        || CommandLine.arguments.contains("--sin-guardar")

    private(set) static var config: Config?
    private(set) static var local: AlmacenLocal?
    static var esLocal: Bool { local != nil }
    static var directorioLocal: URL {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--local-dir"), i + 1 < a.count { return URL(fileURLWithPath:a[i+1], isDirectory:true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/sfmap/Biblioteca", isDirectory:true)
    }
    /// Por qué no hay config, en palabras. Un fallo de credenciales que se
    /// presenta como "no hay páginas" manda a buscar en el sitio equivocado.
    private(set) static var problema: String?

    static func cargarConfig() {
        config = nil; local = nil; problema = nil
        if CommandLine.arguments.contains("--local-dir") || CommandLine.arguments.contains("--local") {
            local = AlmacenLocal(raiz:directorioLocal); return
        }
        let rutas = [
            "\(NSHomeDirectory())/.sfmap/env",
        ]
        for r in rutas {
            guard let txt = try? String(contentsOfFile: r, encoding: .utf8) else { continue }
            var m: [String: String] = [:]
            for l in txt.split(separator: "\n") {
                let s = l.trimmingCharacters(in: .whitespaces)
                guard !s.hasPrefix("#"), let i = s.firstIndex(of: "=") else { continue }
                m[String(s[s.startIndex..<i])] = String(s[s.index(after: i)...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
            if m["MC_SUPABASE_URL"] != nil || m["MC_SUPABASE_KEY"] != nil || m["MC_USER_ID"] != nil {
                do { config = try configuracionRemota(m) }
                catch { problema = error.localizedDescription }
                guard config != nil else { traza("config: configuración remota incompleta"); return }
                traza("config: nube configurada desde \(r)")
                return
            }
        }
        local = AlmacenLocal(raiz:directorioLocal)
        traza("biblioteca local · sin conexión privada")
    }

    /// Solo se conecta a una nube configurada explícitamente por su propietario.
    static func configuracionRemota(_ valores: [String: String]) throws -> Config {
        guard let url = valores["MC_SUPABASE_URL"], let u = URL(string: url),
              ["https", "http"].contains(u.scheme?.lowercased() ?? ""), u.host != nil,
              let key = valores["MC_SUPABASE_KEY"], !key.isEmpty,
              let owner = valores["MC_USER_ID"], let uuid = UUID(uuidString: owner) else {
            throw Err.http("Completa MC_SUPABASE_URL, MC_SUPABASE_KEY y MC_USER_ID (UUID) en ~/.sfmap/env, o usa --local.")
        }
        return Config(url: url.hasSuffix("/") ? String(url.dropLast()) : url,
                      key: key, owner: uuid.uuidString.lowercased())
    }

    static func pedir(_ ruta: String, metodo: String = "GET",
                              cuerpo: Data? = nil) async throws -> Data {
        guard let c = config else { throw Err.sinConfig }
        var req = URLRequest(url: URL(string: c.url + ruta)!)
        req.httpMethod = metodo
        req.setValue(c.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(c.key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if metodo == "PATCH" || metodo == "POST" { req.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        req.httpBody = cuerpo
        let (d, r) = try await URLSession.shared.data(for: req)
        guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            throw Err.http(String(data: d, encoding: .utf8) ?? "?")
        }
        return d
    }

    enum Err: Error, LocalizedError {
        case sinConfig, http(String)
        var errorDescription: String? {
            switch self {
            case .sinConfig: return problema ?? "sin configuración"
            case .http(let m): return m
            }
        }
    }

    // ── listar ──────────────────────────────────────────────────────────────
    static func paginas() async throws -> ([ResumenPagina], [Carpeta]) {
        if let local { return try await local.listar() }
        /*
         * ⚠️ NO SE PIDE `page_elements` PARA LISTAR.
         *
         * Medido el 20 ago 2026: pedirlo bajaba **31.92 MB en 8.0 s**; sin él
         * son **0.02 MB en 0.56 s**. Factor 1,600 en lo PRIMERO que hace la
         * app, y todo para poner un número al lado de cada nombre.
         *
         * Es el error clásico de traerse el documento entero para calcular una
         * propiedad de su tamaño. El contador se rellena al ABRIR la página,
         * que es cuando los elementos hacen falta de verdad.
         */
        let d = try await pedir("/rest/v1/draw?\(filtroDueno)&select=page_id,name,folder_id,settings&order=updated_at.desc")
        let filas = try JSONDecoder().decode([Json].self, from: d)
        traza("paginas: \(filas.count) filas del servidor")
        let ps: [ResumenPagina] = filas.compactMap { f in
            // Las hojas HTML no se listan: no tienen elementos que pintar, y
            // ofrecerlas seria prometer una pagina que abre en blanco.
            if f["settings"]?["htmlUrl"] != nil { return nil }
            guard let id = f["page_id"]?.s else { return nil }
            return ResumenPagina(id: id, nombre: f["name"]?.s ?? "Sin título",
                                 folderId: f["folder_id"]?.s, elementos: -1)
        }
        var cs: [Carpeta] = []
        if let dc = try? await pedir("/rest/v1/draw_folders?user_id=eq.\(dueno)&select=id,name,parent_id&order=name"),
           let fc = try? JSONDecoder().decode([Json].self, from: dc) {
            cs = fc.compactMap { c in
                guard let id = c["id"]?.s else { return nil }
                return Carpeta(id: id, nombre: c["name"]?.s ?? "?", madre: c["parent_id"]?.s)
            }
        }
        traza("paginas: \(ps.count) utiles, \(cs.count) carpetas")
        return (ps, cs)
    }

    // ── abrir ───────────────────────────────────────────────────────────────
    struct Pagina { var id: String; var nombre: String; var elementos: [Elemento]; var camara: Camara?; var version: Double; var documento: Json = .objeto([:]) }

    static func abrir(_ id: String) async throws -> Pagina {
        if let local { return try await local.abrir(id) }
        let d = try await pedir("/rest/v1/draw?page_id=eq.\(id)&select=page_id,name,page_elements,agent_version")
        let filas = try JSONDecoder().decode([Json].self, from: d)
        guard let f = filas.first else { throw Err.http("no existe la página \(id)") }
        let doc = f["page_elements"]
        let els = (doc?["elements"]?.arr ?? []).map(Elemento.init)
        var cam: Camara?
        if let c = doc?["camera"], c["zoom"]?.num != nil {
            cam = Camara(x: c["x"]?.num ?? 0, y: c["y"]?.num ?? 0, zoom: c["zoom"]?.num ?? 1)
        }
        return Pagina(id: id, nombre: f["name"]?.s ?? "Sin título",
                      elementos: els, camara: cam, version: f["agent_version"]?.num ?? 0, documento:doc ?? .objeto([:]))
    }

    // ── guardar ─────────────────────────────────────────────────────────────
    /// Escribe el documento COMPLETO, conservando lo que sfmap no conoce.
    ///
    /// ⚠️ Se re-lee la fila antes de escribir para conservar `regions` — la capa
    /// semántica que el compilador guarda y que sfmap no toca. El lienzo v3
    /// vació esa capa exactamente así: un guardado que sobrescribe el objeto
    /// entero con las claves que sí conoce.
    static func guardar(_ p: Pagina) async throws -> Double {
        if let local { return try await local.guardar(p) }
        guard !soloLectura else { throw Err.http("modo solo lectura: no se escribe nada") }
        let d = try await pedir("/rest/v1/draw?page_id=eq.\(p.id)&select=page_elements,agent_version")
        let filas = try JSONDecoder().decode([Json].self, from: d)
        let previo = filas.first?["page_elements"]
        let versionServidor = filas.first?["agent_version"]?.num ?? 0
        guard versionServidor <= p.version else {
            throw Err.http("la página cambió en otro sitio (v\(Int(versionServidor)) vs v\(Int(p.version))); recárgala")
        }

        let doc = documentoActualizado(p, previo: previo ?? .objeto([:]))

        let cuerpo = try JSONEncoder().encode(Json.objeto([
            "page_elements": doc,
            "agent_version": .numero(versionServidor + 1),
            "updated_at": .texto(ISO8601DateFormatter().string(from: Date())),
        ]))
        let resp = try await pedir("/rest/v1/draw?page_id=eq.\(p.id)&agent_version=eq.\(Int(versionServidor))", metodo: "PATCH", cuerpo: cuerpo)
        // CERO FILAS ES UN ERROR, nunca un éxito silencioso. El v3 marcaba
        // "Guardado" con cero filas afectadas y pasó dos días sin persistir.
        let escritas = (try? JSONDecoder().decode([Json].self, from: resp))?.count ?? 0
        guard escritas > 0 else { throw Err.http("no se escribió ninguna fila") }
        return versionServidor + 1
    }

    static func documentoActualizado(_ p: Pagina, previo: Json) -> Json {
        var doc = previo.con("schemaVersion", .numero(Double(esquemaV4)))
            .con("elements", .lista(p.elementos.map(\.crudo)))
        if let c = p.camara { doc = doc.con("camera", .objeto(["x":.numero(c.x), "y":.numero(c.y), "zoom":.numero(c.zoom)])) }
        return doc
    }
}
