import XCTest
import AppKit
@testable import SFMap

final class DocumentosLienzoTests: XCTestCase {
    func testPreferenciaEmpiezaApagadaYSeRecuerda() {
        let nombre = "sfmap.test.docs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: nombre)!
        defer { defaults.removePersistentDomain(forName: nombre) }
        XCTAssertFalse(DocumentosLienzo.leer(defaults))
        DocumentosLienzo.guardar(true, en: defaults)
        XCTAssertTrue(DocumentosLienzo.leer(UserDefaults(suiteName: nombre)!))
        DocumentosLienzo.guardar(false, en: defaults)
        XCTAssertFalse(DocumentosLienzo.leer(defaults))
    }

    func testApagadoBloqueaDocsSinBloquearNavegacion() {
        XCTAssertFalse(DocumentosLienzo.permite("doc:README.md", activos: false))
        for liga in ["page:otra", "node:oferta", "https://example.com", "app:sfcal"] {
            XCTAssertTrue(DocumentosLienzo.permite(liga, activos: false), liga)
        }
    }

    func testGestosDeDocumentoSoloAbrenConInterruptorActivo() {
        // Título, marca, Cmd+clic e imagen con doble clic.
        for activo in [false, true] {
            for gesto in 0..<4 {
                let e = Elemento(.objeto(["id":.texto("doc"), "type":.texto(gesto == 0 ? "text" : "image"),
                    "text":.texto("La oferta"), "x":.numero(0), "y":.numero(0),
                    "width":.numero(200), "height":.numero(120), "link":.texto("doc:README.md"),
                    "openOnClick":.bool(gesto == 0)]))
                let w = NSWindow(contentRect: NSRect(x:0,y:0,width:800,height:600), styleMask:.borderless, backing:.buffered, defer:false)
                let l = Lienzo(frame:w.contentView!.bounds); w.contentView=l
                l.doc.cargar([e]); l.camara=Camara(x:0,y:0,zoom:1); l.documentosActivos=activo
                var abiertos=0; l.alAbrirEnlace={ _ in abiertos += 1 }
                let p=gesto == 1 ? Pintor.centroMarca(e,zoom:1) : CGPoint(x:100,y:60)
                let v=CGPoint(x:p.x+l.bounds.width/2,y:p.y+l.bounds.height/2)
                func evento(_ tipo:NSEvent.EventType) -> NSEvent {
                    NSEvent.mouseEvent(with:tipo,location:l.convert(v,to:nil),modifierFlags:gesto == 2 ? .command : [],timestamp:1,windowNumber:w.windowNumber,context:nil,eventNumber:0,clickCount:gesto == 3 ? 2 : 1,pressure:1)!
                }
                l.mouseDown(with:evento(.leftMouseDown)); l.mouseUp(with:evento(.leftMouseUp))
                XCTAssertEqual(abiertos,activo ? 1 : 0,"gesto \(gesto), activo \(activo)")
                if !activo && gesto == 0 { XCTAssertEqual(l.doc.seleccion,["doc"]) }
            }
        }
    }

    func testApagarEntrePresionarYSoltarCancelaDocumento() {
        let e=Elemento(.objeto(["id":.texto("d"),"type":.texto("text"),"text":.texto("Oferta"),"x":.numero(0),"y":.numero(0),"width":.numero(200),"height":.numero(120),"link":.texto("doc:a.md"),"openOnClick":.bool(true)]))
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),styleMask:.borderless,backing:.buffered,defer:false)
        let l=Lienzo(frame:w.contentView!.bounds);w.contentView=l;l.doc.cargar([e]);l.camara=Camara(x:0,y:0,zoom:1)
        var abiertos=0;l.alAbrirEnlace={_ in abiertos += 1};l.documentosActivos=true
        func evento(_ tipo:NSEvent.EventType)->NSEvent { NSEvent.mouseEvent(with:tipo,location:l.convert(CGPoint(x:500,y:360),to:nil),modifierFlags:[],timestamp:1,windowNumber:w.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)! }
        l.mouseDown(with:evento(.leftMouseDown));l.documentosActivos=false;l.mouseUp(with:evento(.leftMouseUp))
        XCTAssertEqual(abiertos,0)
    }

    func testBarraCompactaConservaDetalleEnElPuntoYToggle() {
        let b=BarraEstado(frame:.zero), ancho=b.anchoIdeal
        b.estado="doc · una/ruta/muy/larga.md"
        XCTAssertEqual(b.anchoIdeal,ancho)
        XCTAssertFalse(b.subviews.compactMap{$0 as? NSTextField}.contains{$0.stringValue.contains("doc ·")})
        XCTAssertTrue(b.subviews.contains{$0.toolTip?.contains("una/ruta") == true})
        let botones=b.subviews.compactMap{$0 as? BotonPlano}
        XCTAssertFalse(botones.contains{["Acercar","Alejar","Tema claro / oscuro","Exportar PNG"].contains($0.globo ?? "")})
        XCTAssertFalse(botones.contains{$0.accessibilityLabel() == "Abrir documentos al pulsar"}) // En Ajustes
        b.esError=true;b.estado="No hay conexión"
        XCTAssertTrue(b.subviews.contains{$0.toolTip?.contains("No hay conexión") == true})
    }
}
