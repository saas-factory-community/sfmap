import Foundation

/// El alta, el nombre, el borrado y las carpetas de las paginas.
///
/// Todo va DIRECTO a Supabase por REST, igual que leer y guardar: sfmap tiene
/// que poder crear un lienzo aunque el `npm run dev` de Arbrain no este
/// levantado. Una app de escritorio que depende de que otro proceso este
/// corriendo no es una app, es una pestaña con marco.
extension Nube {

    static func pedirPublico(_ ruta: String, metodo: String = "GET", cuerpo: Data? = nil) async throws -> Data {
        try await pedir(ruta, metodo: metodo, cuerpo: cuerpo)
    }

    // ── paginas ─────────────────────────────────────────────────────────────

    static func crearPagina(nombre: String = "Lienzo nuevo", carpeta: String? = nil) async throws -> ResumenPagina {
        let cuerpo = try JSONEncoder().encode(Json.objeto([
            "user_id": .texto(dueno),
            "name": .texto(nombre),
            "folder_id": carpeta.map { Json.texto($0) } ?? .nulo,
            "page_elements": .objeto([
                "schemaVersion": .numero(Double(esquemaV4)),
                "elements": .lista([]),
                "camera": .objeto(["x": .numero(0), "y": .numero(0), "zoom": .numero(1)]),
            ]),
            "agent_version": .numero(1),
            "is_deleted": .bool(false),
        ]))
        let d = try await pedir("/rest/v1/draw?select=page_id,name,folder_id", metodo: "POST", cuerpo: cuerpo)
        guard let f = (try? JSONDecoder().decode([Json].self, from: d))?.first,
              let id = f["page_id"]?.s else { throw Err.http("el servidor no devolvió la página nueva") }
        return ResumenPagina(id: id, nombre: f["name"]?.s ?? nombre, folderId: f["folder_id"]?.s, elementos: 0)
    }

    static func renombrarPagina(_ id: String, _ nombre: String) async throws {
        let cuerpo = try JSONEncoder().encode(Json.objeto([
            "name": .texto(nombre), "updated_at": .texto(ISO8601DateFormatter().string(from: Date())),
        ]))
        let d = try await pedir("/rest/v1/draw?page_id=eq.\(id)&select=page_id", metodo: "PATCH", cuerpo: cuerpo)
        try exigirUnaFila(d, "no se renombró ninguna página")
    }

    /// El borrado es LOGICO. Un lienzo con meses de trabajo no se destruye por
    /// un clic: se marca, deja de listarse, y sigue en la tabla si hay que
    /// recuperarlo.
    static func borrarPagina(_ id: String) async throws {
        let cuerpo = try JSONEncoder().encode(Json.objeto([
            "is_deleted": .bool(true), "updated_at": .texto(ISO8601DateFormatter().string(from: Date())),
        ]))
        let d = try await pedir("/rest/v1/draw?page_id=eq.\(id)&select=page_id", metodo: "PATCH", cuerpo: cuerpo)
        try exigirUnaFila(d, "no se borró ninguna página")
    }

    static func moverPagina(_ id: String, aCarpeta carpeta: String?) async throws {
        let cuerpo = try JSONEncoder().encode(Json.objeto([
            "folder_id": carpeta.map { Json.texto($0) } ?? .nulo,
            "updated_at": .texto(ISO8601DateFormatter().string(from: Date())),
        ]))
        let d = try await pedir("/rest/v1/draw?page_id=eq.\(id)&select=page_id", metodo: "PATCH", cuerpo: cuerpo)
        try exigirUnaFila(d, "no se movió ninguna página")
    }

    // ── carpetas ────────────────────────────────────────────────────────────

    static func crearCarpeta(_ nombre: String = "Carpeta nueva", madre: String? = nil) async throws -> Carpeta {
        var campos: [String: Json] = ["user_id": .texto(dueno), "name": .texto(nombre)]
        if let m = madre { campos["parent_id"] = .texto(m) }
        let cuerpo = try JSONEncoder().encode(Json.objeto(campos))
        let d = try await pedir("/rest/v1/draw_folders?select=id,name,parent_id", metodo: "POST", cuerpo: cuerpo)
        guard let f = (try? JSONDecoder().decode([Json].self, from: d))?.first,
              let id = f["id"]?.s else { throw Err.http("el servidor no devolvió la carpeta nueva") }
        return Carpeta(id: id, nombre: f["name"]?.s ?? nombre, madre: f["parent_id"]?.s)
    }

    /// Mete o saca una carpeta de otra. UN nivel: el llamador garantiza que la
    /// madre no tiene madre — si no, se formarian cadenas y el arbol dejaria de
    /// caber en el panel.
    static func anidarCarpeta(_ id: String, en madre: String?) async throws {
        let cuerpo = try JSONEncoder().encode(Json.objeto(["parent_id": madre.map { Json.texto($0) } ?? .nulo]))
        let d = try await pedir("/rest/v1/draw_folders?id=eq.\(id)&select=id", metodo: "PATCH", cuerpo: cuerpo)
        try exigirUnaFila(d, "no se movió ninguna carpeta")
    }

    static func renombrarCarpeta(_ id: String, _ nombre: String) async throws {
        let cuerpo = try JSONEncoder().encode(Json.objeto(["name": .texto(nombre)]))
        let d = try await pedir("/rest/v1/draw_folders?id=eq.\(id)&select=id", metodo: "PATCH", cuerpo: cuerpo)
        try exigirUnaFila(d, "no se renombró ninguna carpeta")
    }

    /// Borrar una carpeta SUELTA sus paginas, jamas las borra con ella. Es la
    /// diferencia entre ordenar y perder trabajo.
    static func borrarCarpeta(_ id: String) async throws {
        // Y suelta a sus HIJAS igual que a sus paginas: borrar el contenedor
        // jamas se lleva el contenido.
        let sinMadre = try JSONEncoder().encode(Json.objeto(["parent_id": .nulo]))
        _ = try? await pedir("/rest/v1/draw_folders?parent_id=eq.\(id)&select=id", metodo: "PATCH", cuerpo: sinMadre)
        let soltar = try JSONEncoder().encode(Json.objeto(["folder_id": .nulo]))
        _ = try? await pedir("/rest/v1/draw?folder_id=eq.\(id)&select=page_id", metodo: "PATCH", cuerpo: soltar)
        _ = try await pedir("/rest/v1/draw_folders?id=eq.\(id)&select=id", metodo: "DELETE")
    }

    // ── sincronía ───────────────────────────────────────────────────────────

    /**
     * La VERSION de una pagina, sin traerse el documento.
     *
     * Es el sensor de la sincronia: si la version del servidor subio y no fuimos
     * nosotros, alguien la edito en la web o en otro dispositivo.
     *
     * ⚠️ Es un SONDEO, no un canal en vivo, y se dice a proposito. Supabase
     * Realtime habla su propio protocolo sobre WebSocket, y escribir ese cliente
     * en Swift es un proyecto aparte con su propia superficie de fallo — de las
     * que se ven sanas cuando estan muertas. Un GET de dos campos cada pocos
     * segundos cuesta ~200 bytes, y el precio se paga en LATENCIA (se entera en
     * segundos, no al instante), que es visible y honesto.
     */
    static func version(_ id: String) async -> Double? {
        guard let d = try? await pedir("/rest/v1/draw?page_id=eq.\(id)&select=agent_version") else { return nil }
        return (try? JSONDecoder().decode([Json].self, from: d))?.first?["agent_version"]?.num
    }

    /// CERO FILAS ES UN ERROR, nunca un exito silencioso. El v3 marcaba
    /// "Guardado" con cero filas afectadas y paso dos dias sin persistir.
    private static func exigirUnaFila(_ d: Data, _ mensaje: String) throws {
        let n = (try? JSONDecoder().decode([Json].self, from: d))?.count ?? 0
        guard n > 0 else { throw Err.http(mensaje) }
    }
}
