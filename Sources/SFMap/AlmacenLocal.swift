import Foundation

/// Biblioteca personal sin credenciales. Índice ligero + un documento por archivo.
/// Nunca se activa por un fallo de red: sólo al arrancar sin configuración de nube.
actor AlmacenLocal {
    let raiz: URL
    init(raiz: URL) { self.raiz = raiz }
    private var indiceURL: URL { raiz.appendingPathComponent("indice.json") }
    private func paginaURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw Nube.Err.http("Identificador local inválido") }
        return raiz.appendingPathComponent(id + ".json")
    }
    private func leerIndice() throws -> Json {
        if !FileManager.default.fileExists(atPath: indiceURL.path) {
            return .objeto(["paginas":.lista([]), "carpetas":.lista([])])
        }
        return try JSONDecoder().decode(Json.self, from: Data(contentsOf: indiceURL))
    }
    private func escribir(_ j: Json, en url: URL) throws {
        guard !Nube.soloLectura else { throw Nube.Err.http("Modo solo lectura") }
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        try JSONEncoder().encode(j).write(to: url, options: .atomic)
    }
    func listar() throws -> ([ResumenPagina], [Carpeta]) {
        let i = try leerIndice()
        return ((i["paginas"]?.arr ?? []).filter { $0["is_deleted"]?.b != true }.compactMap { p in
            guard let id = p["id"]?.s else { return nil }
            return ResumenPagina(id:id, nombre:p["nombre"]?.s ?? "Sin título", folderId:p["carpeta"]?.s, elementos:-1)
        }, (i["carpetas"]?.arr ?? []).compactMap { c in
            guard let id = c["id"]?.s else { return nil }
            return Carpeta(id:id, nombre:c["nombre"]?.s ?? "Carpeta", madre:c["madre"]?.s)
        })
    }
    /// Primer arranque: sólo una biblioteca que NUNCA tuvo índice recibe la plantilla incluida.
    /// Si la persona borra ese lienzo después, no reaparece: el índice ya existe.
    func sembrar(_ c: ArchivoSFMap.Contenido) throws -> ResumenPagina? {
        guard !FileManager.default.fileExists(atPath: indiceURL.path) else { return nil }
        return try crear(nombre: c.nombre, carpeta: nil, documento: c.documento)
    }
    func abrir(_ id: String) throws -> Nube.Pagina {
        let j = try JSONDecoder().decode(Json.self, from: Data(contentsOf: paginaURL(id)))
        let d = j["documento"] ?? .objeto([:])
        let c = d["camera"]
        return Nube.Pagina(id:id, nombre:j["nombre"]?.s ?? "Sin título",
            elementos:(d["elements"]?.arr ?? []).map(Elemento.init),
            camara:c.map { Camara(x:$0["x"]?.num ?? 0, y:$0["y"]?.num ?? 0, zoom:$0["zoom"]?.num ?? 1) },
            version:j["version"]?.num ?? 1, documento:d)
    }
    func crear(nombre: String, carpeta: String?, documento: Json? = nil) throws -> ResumenPagina {
        let id = UUID().uuidString.lowercased()
        let d = documento ?? .objeto(["schemaVersion":.numero(4), "elements":.lista([])])
        var i = try leerIndice()
        var ps = i["paginas"]?.arr ?? []
        ps.insert(.objeto(["id":.texto(id), "nombre":.texto(nombre), "carpeta":carpeta.map(Json.texto) ?? .nulo]), at:0)
        try escribir(.objeto(["nombre":.texto(nombre), "version":.numero(1), "documento":d]), en:paginaURL(id))
        i = i.con("paginas", .lista(ps)); try escribir(i, en:indiceURL)
        return ResumenPagina(id:id, nombre:nombre, folderId:carpeta, elementos:d["elements"]?.arr?.count ?? 0)
    }
    func guardar(_ p: Nube.Pagina) throws -> Double {
        let anterior = try abrir(p.id)
        guard anterior.version == p.version else { throw Nube.Err.http("El lienzo cambió; recárgalo antes de guardar") }
        let v = anterior.version + 1
        let d = Nube.documentoActualizado(p, previo:anterior.documento)
        try escribir(.objeto(["nombre":anterior.nombre.json, "version":.numero(v), "documento":d]), en:paginaURL(p.id))
        return v
    }
    func editarPagina(_ id: String, campos: [String:Json]) throws {
        var i = try leerIndice(); var ps = i["paginas"]?.arr ?? []
        guard let n = ps.firstIndex(where:{$0["id"]?.s == id}) else { throw Nube.Err.http("No existe el lienzo") }
        for (k,v) in campos { ps[n] = ps[n].con(k,v) }
        if let nombre = campos["nombre"] {
            let url = try paginaURL(id)
            let j = try JSONDecoder().decode(Json.self, from:Data(contentsOf:url))
            try escribir(j.con("nombre",nombre).con("version",.numero((j["version"]?.num ?? 0)+1)), en:url)
        }
        i = i.con("paginas",.lista(ps)); try escribir(i,en:indiceURL)
    }
    func crearCarpeta(_ nombre: String, madre: String?) throws -> Carpeta {
        let id = UUID().uuidString.lowercased(); var i = try leerIndice()
        var cs = i["carpetas"]?.arr ?? []
        cs.append(.objeto(["id":.texto(id),"nombre":.texto(nombre),"madre":madre.map(Json.texto) ?? .nulo]))
        i = i.con("carpetas",.lista(cs)); try escribir(i,en:indiceURL)
        return Carpeta(id:id,nombre:nombre,madre:madre)
    }
    func editarCarpeta(_ id: String, campos: [String:Json], borrar: Bool = false) throws {
        var i = try leerIndice(); var cs = i["carpetas"]?.arr ?? []
        guard let n = cs.firstIndex(where:{$0["id"]?.s == id}) else { throw Nube.Err.http("No existe la carpeta") }
        if borrar {
            cs.remove(at:n)
            cs = cs.map { $0["madre"]?.s == id ? $0.con("madre",.nulo) : $0 }
            i = i.con("paginas",.lista((i["paginas"]?.arr ?? []).map { $0["carpeta"]?.s == id ? $0.con("carpeta",.nulo) : $0 }))
        } else { for (k,v) in campos { cs[n] = cs[n].con(k,v) } }
        try escribir(i.con("carpetas",.lista(cs)),en:indiceURL)
    }
}
private extension String { var json: Json { .texto(self) } }
