import Foundation

/**
 * LA PUERTA DEL COMPILADOR.
 *
 * Es lo único que sigue viviendo en Node, y está bien que siga ahí: compilar un
 * diagrama cuesta ~110 ms y pasa UNA VEZ por diagrama; mover el ratón pasa 120
 * veces por segundo. Reescribir el layout de grafos y la medición con fontkit en
 * Swift serían meses para ganar en el eje que no aprieta.
 *
 * QUÉ MANDA sfmap. No inventa semántica: reenvía el SPEC QUE YA ESTÁ GUARDADO
 * con la página (`page_elements.regions`). Eso es exactamente "recompilar": el
 * servidor vuelve a medir, componer, rutear y RECONCILIAR contra lo que hay —
 * actualiza lo que cambió, agrega lo nuevo, quita lo que se fue, y NO TOCA lo
 * que la mano fijó.
 *
 * ⚠️ Y por eso el botón solo aparece cuando la página TIENE una región. Un botón
 * de recompilar sobre un lienzo dibujado a mano no tendría nada que compilar: es
 * la clase de capacidad prometida y vacía que este proyecto persigue.
 */
enum Compilador {

    struct Region { var id: String; var spec: Json; var version: Double }

    /// La base del servidor de Next. Se puede mover con `SFMAP_CANVAS_URL` por
    /// si Daniel lo levanta en otro puerto.
    static var base: String {
        ProcessInfo.processInfo.environment["SFMAP_CANVAS_URL"] ?? "http://localhost:3000"
    }

    /// El token del agente, del mismo `.env` que la credencial de la base.
    private(set) static var token: String?

    static func cargarToken() {
        let rutas = ["\(NSHomeDirectory())/.sfmap/env"]
        for r in rutas {
            guard let txt = try? String(contentsOfFile: r, encoding: .utf8) else { continue }
            for l in txt.split(separator: "\n") {
                let s = l.trimmingCharacters(in: .whitespaces)
                guard s.hasPrefix("OPENCLAW_GATEWAY_TOKEN="), let i = s.firstIndex(of: "=") else { continue }
                token = String(s[s.index(after: i)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                return
            }
        }
    }

    /// Las regiones GOBERNADAS de una página, leídas del documento guardado.
    static func regiones(_ paginaId: String) async -> [Region] {
        guard let d = try? await Nube.pedir("/rest/v1/draw?page_id=eq.\(paginaId)&select=page_elements"),
              let fila = (try? JSONDecoder().decode([Json].self, from: d))?.first,
              let rs = fila["page_elements"]?["regions"]?.arr else { return [] }
        return rs.compactMap { r in
            guard let id = r["id"]?.s, let spec = r["spec"] else { return nil }
            return Region(id: id, spec: spec, version: r["version"]?.num ?? 0)
        }
    }

    struct Resultado { var agregados: Int; var actualizados: Int; var quitados: Int; var fijados: Int }

    /**
     * Recompila una región. Devuelve el resumen que el servidor reporta.
     *
     * Errores DICHOS, no tragados: si el servidor de Next no está levantado, el
     * mensaje lo dice con esas palabras. Un "no pasó nada" manda a buscar el
     * fallo en el sitio equivocado — y aquí el sitio correcto casi siempre es
     * "no hay servidor".
     */
    static func recompilar(_ paginaId: String, _ region: Region, tema: String) async throws -> Resultado {
        guard let t = token else { throw Nube.Err.http("sin OPENCLAW_GATEWAY_TOKEN en ~/.sfmap/env") }
        var req = URLRequest(url: URL(string: "\(base)/api/canvas/pages/\(paginaId)/region")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Json.objeto([
            "spec": region.spec,
            "regionId": .texto(region.id),
            "theme": .texto(tema),
        ]))
        let (d, r): (Data, URLResponse)
        do { (d, r) = try await URLSession.shared.data(for: req) }
        catch {
            throw Nube.Err.http("el compilador no responde en \(base) — ¿está levantado `npm run dev` en arbrain?")
        }
        guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            let cuerpo = String(data: d, encoding: .utf8) ?? "?"
            throw Nube.Err.http("el compilador devolvió \((r as? HTTPURLResponse)?.statusCode ?? 0): \(cuerpo.prefix(180))")
        }
        let j = try JSONDecoder().decode(Json.self, from: d)
        guard (j["ok"]?.b ?? false) else {
            throw Nube.Err.http(j["error"]?.s ?? "el compilador rechazó la petición")
        }
        let dif = j["diff"] ?? j["resumen"] ?? .objeto([:])
        return Resultado(agregados: Int(dif["added"]?.num ?? dif["agregados"]?.num ?? 0),
                         actualizados: Int(dif["updated"]?.num ?? dif["actualizados"]?.num ?? 0),
                         quitados: Int(dif["removed"]?.num ?? dif["quitados"]?.num ?? 0),
                         fijados: Int(dif["pinned"]?.num ?? dif["fijados"]?.num ?? 0))
    }
}
