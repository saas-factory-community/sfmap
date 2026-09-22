import AppKit
import UniformTypeIdentifiers

/// Un .sfmap es un documento editable y autocontenido, nunca una imagen del lienzo.
enum ArchivoSFMap {
    static let tipo = UTType(exportedAs:"com.saasfactory.sfmap.document", conformingTo:.json)
    static let limite = 128 * 1024 * 1024
    struct Contenido { let nombre:String; let documento:Json; let plantilla:Bool; let enlacesOmitidos:Int }
    enum Fallo: Error, LocalizedError {
        case invalido(String)
        var errorDescription:String? { if case .invalido(let m) = self { return m }; return "Archivo inválido" }
    }
    static func leer(_ data:Data) throws -> Contenido {
        guard data.count <= limite else { throw Fallo.invalido("El archivo supera 128 MB") }
        let j = try JSONDecoder().decode(Json.self,from:data)
        guard j["format"]?.s == "sfmap", j["version"]?.num == 1,
              let doc = j["document"]?.obj, let els = doc["elements"]?.arr,
              els.count <= 20000 else { throw Fallo.invalido("No es un archivo sfmap compatible (versión 1)") }
        var ids = Set<String>()
        for e in els {
            guard let id = e["id"]?.s, !id.isEmpty, ids.insert(id).inserted,
                  e["type"]?.s != nil else { throw Fallo.invalido("Elementos sin identificador o duplicados") }
            for k in ["x","y","width","height","rotation"] {
                if let v = e[k], v.num == nil || !(v.num?.isFinite ?? false) { throw Fallo.invalido("Geometría inválida") }
            }
            if e["type"]?.s == "image" {
                guard let src = e["src"]?.s, try imagenEmbebida(src) != nil else {
                    throw Fallo.invalido("Hay imágenes externas. Exporta de nuevo con sfmap para incluirlas.")
                }
            }
            if e["type"]?.s == "embed" || e["type"]?.s == "html" || e["role"]?.s == "html" || e["html"] != nil || e["role"]?.s == "widget" {
                throw Fallo.invalido("Los objetos HTML y widgets vivos no forman parte del formato portátil todavía")
            }
        }
        if let c = doc["camera"] {
            for k in ["x","y","zoom"] { guard let n = c[k]?.num, n.isFinite else { throw Fallo.invalido("Cámara inválida") } }
            guard (0.01...32).contains(c["zoom"]!.num!) else { throw Fallo.invalido("Zoom inválido") }
        }
        let limpio = sanear(.objeto(doc))
        return Contenido(nombre:j["name"]?.s ?? "Lienzo importado", documento:limpio.0,
            plantilla:j["kind"]?.s == "template", enlacesOmitidos:limpio.1)
    }
    /// Al importar no se leen rutas del equipo receptor ni se abren apps/documentos privados.
    static func sanear(_ j:Json) -> (Json,Int) {
        switch j {
        case .lista(let a):
            var n=0; let v=a.map { x -> Json in let r=sanear(x);n += r.1;return r.0 };return (.lista(v),n)
        case .objeto(let o):
            var v=[String:Json](); var n=0
            for (k,x) in o {
                if k == "link", let s=x.s, !(s.hasPrefix("https://") || s.hasPrefix("http://") || s.hasPrefix("node:")) { n += 1;continue }
                if k == "openOnClick" { v[k] = .bool(false);continue }
                if ["origin","gen","gsig","mano","regions"].contains(k) { continue }
                let r=sanear(x);v[k]=r.0;n += r.1
            }
            return (.objeto(v),n)
        default:return (j,0)
        }
    }
    static func imagenEmbebida(_ src:String) throws -> Data? {
        guard src.hasPrefix("data:image/") else { return nil }
        guard let comma=src.firstIndex(of:","), src[..<comma].contains(";base64"),
              let d=Data(base64Encoded:String(src[src.index(after:comma)...])), d.count <= 32*1024*1024,
              NSImage(data:d) != nil else { throw Fallo.invalido("Imagen dañada o demasiado grande") }
        return d
    }
    static func preparar(nombre:String, documento:Json, plantilla:Bool) async throws -> (Data,Int) {
        var doc=documento
        var els=doc["elements"]?.arr ?? []
        for i in els.indices where els[i]["type"]?.s == "image" {
            guard let src=els[i]["src"]?.s else { throw Fallo.invalido("Imagen sin recurso") }
            if try imagenEmbebida(src) != nil { continue }
            let d:Data
            if let u=URL(string:src), ["https","http"].contains(u.scheme ?? "") {
                let (data,response)=try await URLSession.shared.data(from:u)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Fallo.invalido("No se pudo incluir una imagen remota") };d=data
            } else {
                let url=src.hasPrefix("file:") ? URL(string:src)! : URL(fileURLWithPath:(src as NSString).expandingTildeInPath)
                d=try Data(contentsOf:url)
            }
            guard d.count<=32*1024*1024, let img=NSImage(data:d), let tiff=img.tiffRepresentation,
                  let rep=NSBitmapImageRep(data:tiff), let png=rep.representation(using:.png,properties:[:]) else {
                throw Fallo.invalido("No se pudo incluir una imagen. El archivo original debe estar disponible.")
            }
            els[i]=els[i].con("src",.texto("data:image/png;base64,"+png.base64EncodedString()))
        }
        doc=doc.con("elements",.lista(els))
        let limpio=sanear(doc)
        let env:Json = .objeto(["format":.texto("sfmap"),"version":.numero(1),"kind":.texto(plantilla ? "template":"canvas"),
            "name":.texto(nombre),"document":limpio.0])
        let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys]
        let data=try enc.encode(env)
        _=try leer(data) // Una descarga debe poder volver a abrirse antes de ofrecerla.
        return (data,limpio.1)
    }
}

extension Nube {
    static func importar(_ c:ArchivoSFMap.Contenido, carpeta:String? = nil) async throws -> ResumenPagina {
        guard !soloLectura else { throw Err.http("Modo solo lectura") }
        if let local { return try await local.crear(nombre:c.nombre,carpeta:carpeta,documento:c.documento) }
        let cuerpo = try JSONEncoder().encode(Json.objeto([
            "user_id":.texto(dueno),"name":.texto(c.nombre),"folder_id":carpeta.map(Json.texto) ?? .nulo,
            "page_elements":c.documento,"agent_version":.numero(1),"is_deleted":.bool(false)]))
        let d=try await pedir("/rest/v1/draw?select=page_id,name,folder_id",metodo:"POST",cuerpo:cuerpo)
        guard let f=try JSONDecoder().decode([Json].self,from:d).first, let id=f["page_id"]?.s else { throw Err.http("No se importó ninguna página") }
        return ResumenPagina(id:id,nombre:c.nombre,folderId:carpeta,elementos:c.documento["elements"]?.arr?.count ?? 0)
    }
}
