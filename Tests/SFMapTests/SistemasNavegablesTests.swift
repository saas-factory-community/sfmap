import XCTest
import AppKit
@testable import SFMap

final class SistemasNavegablesTests: XCTestCase {
    func testEsquinasDeSeleccionMixtaConZoomLejano() {
        for esquina in ["nw", "ne", "se", "sw"] {
            var fijo = nodo("fijo", link:nil, clic:false)
            fijo.crudo = fijo.crudo.con("locked", .bool(true))
            var libre = nodo("libre", link:nil, clic:false)
            libre.crudo = libre.crudo.con("x", .numero(300))
            let (l,w) = montar([fijo, libre])
            l.camara.zoom = 0.23
            l.doc.seleccion = ["fijo", "libre"]
            let caja = fijo.cajaVisual.union(libre.cajaVisual)
            let p = Geo.centroManija(caja, esquina)
            let q = CGPoint(x:p.x + (p.x < caja.midX ? 40 : -40),
                            y:p.y + (p.y < caja.midY ? 10 : -10))
            l.mouseMoved(with:evento(.mouseMoved,l,w,p))
            XCTAssertTrue(NSCursor.current === (["nw", "se"].contains(esquina)
                ? NSCursor.redimensionNWSE : NSCursor.redimensionNESW), esquina)
            l.mouseDown(with:evento(.leftMouseDown,l,w,p))
            XCTAssertTrue(l.estadoParaSonda.contains("redimensionar"), esquina)
            l.mouseDragged(with:evento(.leftMouseDragged,l,w,q))
            l.mouseUp(with:evento(.leftMouseUp,l,w,q))
            XCTAssertEqual(l.doc.seleccion, ["fijo", "libre"], esquina)
            XCTAssertEqual(l.doc.porId("fijo")?.crudo, fijo.crudo, esquina)
            XCTAssertLessThan(l.doc.porId("libre")!.ancho, libre.ancho, esquina)
            l.doc.deshacer()
            XCTAssertEqual(l.doc.porId("libre")?.caja, libre.caja, esquina)
            XCTAssertEqual(l.doc.porId("fijo")?.crudo, fijo.crudo, esquina)
        }
    }
    func testTodosBloqueadosNoSeRedimensionan() {
        var fijo = nodo("fijo", link:nil, clic:false)
        fijo.crudo = fijo.crudo.con("locked", .bool(true))
        let (l,w) = montar([fijo]); l.doc.seleccion = ["fijo"]
        let p = Geo.centroManija(fijo.cajaVisual, "se")
        l.mouseDown(with:evento(.leftMouseDown,l,w,p))
        XCTAssertFalse(l.estadoParaSonda.contains("redimensionar"))
        l.mouseDragged(with:evento(.leftMouseDragged,l,w,CGPoint(x:p.x+50,y:p.y+50)))
        l.mouseUp(with:evento(.leftMouseUp,l,w,CGPoint(x:p.x+50,y:p.y+50)))
        XCTAssertEqual(l.doc.porId("fijo")?.crudo, fijo.crudo)
    }
    func nodo(_ id:String="i",link:String?="https://saasfactory.so/about",clic:Bool=true) -> Elemento {
        var j:[String:Json] = ["id":.texto(id),"type":.texto("image"),"x":.numero(0),"y":.numero(0),
            "width":.numero(200),"height":.numero(120),"zIndex":.numero(1),"openOnClick":.bool(clic)]
        if let link { j["link"] = .texto(link) }
        return Elemento(.objeto(j))
    }
    func montar(_ els:[Elemento]) -> (Lienzo,NSWindow) {
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),styleMask:.borderless,backing:.buffered,defer:false)
        let l=Lienzo(frame:w.contentView!.bounds);w.contentView=l;l.doc.cargar(els);l.camara=Camara(x:0,y:0,zoom:1)
        return (l,w)
    }
    func evento(_ tipo:NSEvent.EventType,_ l:Lienzo,_ w:NSWindow,_ p:CGPoint,clics:Int=1,mods:NSEvent.ModifierFlags=[]) -> NSEvent {
        let v=CGPoint(x:(p.x-l.camara.x)*l.camara.zoom+l.bounds.width/2,y:(p.y-l.camara.y)*l.camara.zoom+l.bounds.height/2)
        return NSEvent.mouseEvent(with:tipo,location:l.convert(v,to:nil),modifierFlags:mods,timestamp:1,windowNumber:w.windowNumber,context:nil,eventNumber:0,clickCount:clics,pressure:1)!
    }
    func testClicAbreAlSoltarYNoAlPresionar() {
        let(l,w)=montar([nodo()]);var ligas:[String]=[];l.alAbrirEnlace={ligas.append($0)}
        l.mouseDown(with:evento(.leftMouseDown,l,w,CGPoint(x:100,y:60)))
        XCTAssertTrue(ligas.isEmpty)
        l.mouseUp(with:evento(.leftMouseUp,l,w,CGPoint(x:100,y:60)))
        XCTAssertEqual(ligas,["https://saasfactory.so/about"])
    }
    func testArrastreNoNavegaAunqueRegreseAlOrigen() {
        let(l,w)=montar([nodo()]);var n=0;l.alAbrirEnlace={_ in n+=1}
        l.mouseDown(with:evento(.leftMouseDown,l,w,CGPoint(x:100,y:60)))
        l.mouseDragged(with:evento(.leftMouseDragged,l,w,CGPoint(x:130,y:100)))
        l.mouseDragged(with:evento(.leftMouseDragged,l,w,CGPoint(x:100,y:60)))
        l.mouseUp(with:evento(.leftMouseUp,l,w,CGPoint(x:100,y:60)))
        XCTAssertEqual(n,0)
    }
    func testClicSobreLaMarcaTambienEsperaASoltar() {
        let e=nodo(),(l,w)=montar([e]);var n=0;l.alAbrirEnlace={_ in n+=1}
        let p=Pintor.centroMarca(e,zoom:1)
        l.mouseDown(with:evento(.leftMouseDown,l,w,p))
        XCTAssertEqual(n,0)
        l.mouseUp(with:evento(.leftMouseUp,l,w,p))
        XCTAssertEqual(n,1)
    }
    func testArrastrarDesdeLaMarcaNoAbreLaFuente() {
        let e=nodo(),(l,w)=montar([e]);var n=0;l.alAbrirEnlace={_ in n+=1}
        let p=Pintor.centroMarca(e,zoom:1),q=CGPoint(x:p.x+40,y:p.y+40)
        l.mouseDown(with:evento(.leftMouseDown,l,w,p))
        l.mouseDragged(with:evento(.leftMouseDragged,l,w,q))
        l.mouseUp(with:evento(.leftMouseUp,l,w,q))
        XCTAssertEqual(n,0)
        XCTAssertEqual(l.doc.elementos[0].x,40,accuracy:1)
    }
    func testTemblorDeDosPixelesSigueSiendoClic() {
        let(l,w)=montar([nodo()]);var n=0;l.alAbrirEnlace={_ in n+=1}
        l.mouseDown(with:evento(.leftMouseDown,l,w,CGPoint(x:100,y:60)))
        l.mouseDragged(with:evento(.leftMouseDragged,l,w,CGPoint(x:102,y:60)))
        l.mouseUp(with:evento(.leftMouseUp,l,w,CGPoint(x:102,y:60)))
        XCTAssertEqual(n,1);XCTAssertEqual(l.doc.elementos[0].x,0)
    }
    func testShiftSeleccionaSinNavegar() {
        let(l,w)=montar([nodo()]);var n=0;l.alAbrirEnlace={_ in n+=1}
        l.mouseDown(with:evento(.leftMouseDown,l,w,CGPoint(x:100,y:60),mods:.shift))
        l.mouseUp(with:evento(.leftMouseUp,l,w,CGPoint(x:100,y:60),mods:.shift))
        XCTAssertEqual(n,0);XCTAssertEqual(l.doc.seleccion,["i"])
    }
    func testSoltarFueraNoNavega() {
        let(l,w)=montar([nodo()]);var n=0;l.alAbrirEnlace={_ in n+=1}
        l.mouseDown(with:evento(.leftMouseDown,l,w,CGPoint(x:100,y:60)))
        l.mouseUp(with:evento(.leftMouseUp,l,w,CGPoint(x:500,y:400)))
        XCTAssertEqual(n,0)
    }
    func testLinkInternoYEncuadreNoMutanElDocumento() {
        XCTAssertEqual(Enlace.leer("node:zona:atraer"),.elemento("zona:atraer"))
        XCTAssertNil(Enlace.leer("node: "))
        let(l,_)=montar([nodo()]);let antes=l.doc.elementos[0].crudo
        XCTAssertTrue(l.enfocar("i"));XCTAssertFalse(l.enfocar("ausente"))
        XCTAssertEqual(l.doc.elementos[0].crudo,antes)
        XCTAssertGreaterThan(l.camara.zoom,1)
    }
    func testFichaSeparaDeclaradoDeResultadoMedido() {
        var e=nodo();e.crudo=e.crudo.con("evidence",.lista([.objeto(["url":.texto("https://example.org"),"date":.texto("2026-09-07"),"status":.texto("declared")])]))
        e.crudo=e.crudo.con("decision",.objeto(["question":.texto("Qué validar"),"measure":.texto("Cobros confirmados")]))
        let s=FichaSistema.markdown(e,elementos:[e])
        XCTAssertTrue(s.contains("Declarado por su autor"));XCTAssertTrue(s.contains("todavía no medido"))
        XCTAssertTrue(s.contains("https://example.org"));XCTAssertTrue(s.contains("2026-09-07"))
    }
}

final class TrazoConectorTests:XCTestCase {
    func arista(_ puntos:[CGPoint],curva:Bool=true) -> Elemento {
        Elemento(.objeto(["id":.texto("c"),"type":.texto("connector"),"routing":.texto(curva ? "curva":"ortogonal"),
            "curveStyle":.texto("ports"),"fromPort":.texto("e"),"toPort":.texto("n"),
            "points":.lista(puntos.map{.objeto(["x":.numero($0.x),"y":.numero($0.y)])})]))
    }
    func testCurvaSalePorEsteYEntraPorNorte() {
        let e=arista([.zero,CGPoint(x:200,y:300)]),p=TrazoConector.muestras(e)
        XCTAssertEqual(p.first,.zero);XCTAssertEqual(p.last,CGPoint(x:200,y:300))
        XCTAssertGreaterThan(p[1].x,0);XCTAssertLessThan(p[1].y,1)
        XCTAssertLessThan(p[p.count-2].y,300);XCTAssertEqual(p[p.count-2].x,200,accuracy:1)
    }
    func testAgarreSigueLaCurvaVisible() {
        let e=arista([.zero,CGPoint(x:200,y:300)]),p=TrazoConector.punto(e,t:0.5)
        XCTAssertEqual(Geo.elegir([e],p,zoom:1)?.id,"c")
        XCTAssertNil(Geo.elegir([e],CGPoint(x:-200,y:100),zoom:1))
    }
    func testEtiquetaEnMedioEvitaLasCapturas() {
        let e=arista([CGPoint(x:100,y:100),CGPoint(x:100,y:500)],curva:false)
        let obs=[CGRect(x:0,y:0,width:200,height:150),CGRect(x:0,y:450,width:200,height:150)]
        let caja=TrazoConector.cajaEtiqueta(e,tamano:CGSize(width:100,height:24),obstaculos:obs)
        XCTAssertFalse(obs.contains{$0.intersects(caja)})
        XCTAssertGreaterThan(caja.minY,150);XCTAssertLessThan(caja.maxY,450)
    }
    func testEtiquetaBuscaOtroTramoSiElCentroEstaOcupado() {
        let e=arista([.zero,CGPoint(x:600,y:0)],curva:false),obs=[CGRect(x:200,y:-80,width:200,height:160)]
        let caja=TrazoConector.cajaEtiqueta(e,tamano:CGSize(width:60,height:24),obstaculos:obs)
        XCTAssertFalse(obs[0].intersects(caja))
    }
    func testCodoSuaveConservaExtremosYSuAgarre() {
        var e=arista([.zero,CGPoint(x:300,y:0),CGPoint(x:300,y:800)],curva:false)
        e.crudo=e.crudo.con("cornerRadius",.numero(100))
        let p=TrazoConector.muestras(e)
        XCTAssertEqual(p.first,.zero);XCTAssertEqual(p.last,CGPoint(x:300,y:800))
        XCTAssertFalse(p.contains(CGPoint(x:300,y:0)))
        XCTAssertTrue(p.allSatisfy{$0.x >= 0 && $0.x <= 300 && $0.y >= 0 && $0.y <= 800})
        XCTAssertEqual(Geo.elegir([e],CGPoint(x:275,y:25),zoom:1)?.id,"c")
        XCTAssertNil(Geo.elegir([e],CGPoint(x:300,y:0),zoom:1))
    }
    func testRadioNoSeSaleDeSegmentosCortos() {
        var e=arista([.zero,CGPoint(x:10,y:0),CGPoint(x:10,y:10)],curva:false)
        e.crudo=e.crudo.con("cornerRadius",.numero(1000))
        XCTAssertTrue(TrazoConector.muestras(e).allSatisfy{$0.x >= 0 && $0.x <= 10 && $0.y >= 0 && $0.y <= 10})
    }
    func testRutaConCodosConservaSuGeometria() {
        let ps=[CGPoint.zero,CGPoint(x:300,y:0),CGPoint(x:300,y:800)]
        let e=arista(ps,curva:false)
        XCTAssertEqual(TrazoConector.muestras(e),ps)
        XCTAssertEqual(TrazoConector.punto(e,t:0.5),CGPoint(x:300,y:250))
    }
}
