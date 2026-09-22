import XCTest
import AppKit
@testable import SFMap

final class PortabilidadTests:XCTestCase {
    func doc() -> Json { .objeto(["schemaVersion":.numero(4),"futureField":.texto("preservar"),"regions":.lista([.texto("privado")]),"elements":.lista([
        .objeto(["id":.texto("a"),"type":.texto("text"),"x":.numero(0),"y":.numero(20),"text":.texto("Mi oferta"),"link":.texto("doc:secreto.md"),"future":.numero(9)]),
        .objeto(["id":.texto("b"),"type":.texto("text"),"x":.numero(100),"y":.numero(20),"link":.texto("node:a")]),
        .objeto(["id":.texto("c"),"type":.texto("connector"),"fromId":.texto("a"),"toId":.texto("b")])])]) }
    func testPortableRoundTripConservaContenidoYRelacionesSinVinculosPrivados() async throws {
        for plantilla in [false,true] {
            let (data,n)=try await ArchivoSFMap.preparar(nombre:"Mi negocio",documento:doc(),plantilla:plantilla)
            XCTAssertEqual(n,1)
            let c=try ArchivoSFMap.leer(data)
            XCTAssertEqual(c.plantilla,plantilla);XCTAssertEqual(c.nombre,"Mi negocio")
            XCTAssertEqual(c.documento["futureField"]?.s,"preservar")
            let es=c.documento["elements"]!.arr!
            XCTAssertNil(es[0]["link"]);XCTAssertNil(c.documento["regions"])
            XCTAssertEqual(es[0]["future"]?.num,9);XCTAssertEqual(es[1]["link"]?.s,"node:a")
            XCTAssertEqual(es[2]["fromId"]?.s,"a");XCTAssertEqual(es[2]["toId"]?.s,"b")
        }
    }
    func testImagenViajaSinArchivoOriginal() async throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        try rep.representation(using:.png,properties:[:])!.write(to:url)
        let d:Json = .objeto(["elements":.lista([.objeto(["id":.texto("img"),"type":.texto("image"),"src":.texto(url.path)])])])
        let (data,_)=try await ArchivoSFMap.preparar(nombre:"Foto",documento:d,plantilla:true)
        try FileManager.default.removeItem(at:url)
        let c=try ArchivoSFMap.leer(data)
        XCTAssertNotNil(try ArchivoSFMap.imagenEmbebida(c.documento["elements"]!.arr![0]["src"]!.s!))
    }
    func testRechazaFormatoMaloDuplicadosYRecursosExternos() throws {
        for j:Json in [.objeto([:]),.objeto(["format":.texto("sfmap"),"version":.numero(99)])] {
            XCTAssertThrowsError(try ArchivoSFMap.leer(JSONEncoder().encode(j)))
        }
        let e:Json = .objeto(["id":.texto("a"),"type":.texto("image"),"src":.texto("/etc/passwd")])
        let j:Json = .objeto(["format":.texto("sfmap"),"version":.numero(1),"document":.objeto(["elements":.lista([e])])])
        XCTAssertThrowsError(try ArchivoSFMap.leer(JSONEncoder().encode(j)))
        let dup=j.con("document",.objeto(["elements":.lista([.objeto(["id":.texto("a"),"type":.texto("text")]),.objeto(["id":.texto("a"),"type":.texto("text")])])]))
        XCTAssertThrowsError(try ArchivoSFMap.leer(JSONEncoder().encode(dup)))
    }
    func testBibliotecaLocalCreaEditaReabreYCASNoPierdeTrabajo() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("sfmap-test-"+UUID().uuidString)
        let store=AlmacenLocal(raiz:root)
        let c=try await store.crearCarpeta("Negocio",madre:nil)
        let p=try await store.crear(nombre:"Mapa",carpeta:c.id,documento:doc())
        var a=try await store.abrir(p.id)
        a.elementos[0].crudo=a.elementos[0].crudo.con("text",.texto("Editado"))
        let v=try await store.guardar(a);XCTAssertEqual(v,2)
        do { _=try await store.guardar(a);XCTFail("No debe aceptar versión vieja") } catch {}
        let reopened=try await AlmacenLocal(raiz:root).abrir(p.id)
        XCTAssertEqual(reopened.elementos[0].crudo["text"]?.s,"Editado")
        XCTAssertEqual(reopened.documento["futureField"]?.s,"preservar")
        XCTAssertNotNil(reopened.documento["regions"])
        try await store.editarCarpeta(c.id,campos:[:],borrar:true)
        var ps=try await store.listar().0;XCTAssertNil(ps[0].folderId)
        try await store.editarPagina(p.id,campos:["is_deleted":.bool(true)])
        ps=try await store.listar().0;XCTAssertTrue(ps.isEmpty)
        let saved=try await store.abrir(p.id);XCTAssertEqual(saved.elementos.count,3) // Borrado lógico
    }
    func testPreferenciaMinimapaPersisteYDocsPorDefectoApagados() {
        let key="sfmap.test."+UUID().uuidString;let d=UserDefaults(suiteName:key)!
        defer { d.removePersistentDomain(forName:key) }
        XCTAssertTrue(PreferenciasLienzo.minimapa(d));XCTAssertFalse(DocumentosLienzo.leer(d))
        PreferenciasLienzo.fijarMinimapa(false,d);XCTAssertFalse(PreferenciasLienzo.minimapa(UserDefaults(suiteName:key)!))
    }
    func testGuardarConservaTodosLosCamposDelDocumento() {
        let p=Nube.Pagina(id:"a",nombre:"m",elementos:[],camara:nil,version:1)
        let j=Nube.documentoActualizado(p,previo:doc())
        XCTAssertEqual(j["futureField"],doc()["futureField"]);XCTAssertEqual(j["regions"],doc()["regions"])
    }
}
