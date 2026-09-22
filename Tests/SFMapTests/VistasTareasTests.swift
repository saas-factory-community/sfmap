import XCTest
@testable import SFMap
final class VistasTareasTests:XCTestCase {
    func testHoyNoArrastraMananaYRespetaHaciendo() throws {
        let now=try XCTUnwrap(GDate.dayOnly.date(from:"2026-09-12"))
        let actual=TareaDia(id:"a",contenido:"Clase",prioridad:2,dia:nil,hora:nil,frente:nil,frenteId:nil,estado:"Haciendo")
        let future=TareaDia(id:"b",contenido:"Mañana",prioridad:1,dia:"2026-09-13",hora:nil,frente:nil,frenteId:nil)
        let g=VistaTareas.grupos([actual,future],hoy:now,vista:.hoy)
        XCTAssertEqual(g.flatMap{$0.1}.map(\.id),["a"])
        XCTAssertTrue(VistaTareas.grupos([future],hoy:now,vista:.hoy).flatMap{$0.1}.isEmpty)
    }
    func testSieteDiasIncluyeHoyYSeisSiguientes() throws {
        let now=try XCTUnwrap(GDate.dayOnly.date(from:"2026-09-12"))
        let tasks=["2026-09-18","2026-09-19"].enumerated().map { i,d in TareaDia(id:String(i),contenido:d,prioridad:2,dia:d,hora:nil,frente:nil,frenteId:nil) }
        XCTAssertEqual(VistaTareas.grupos(tasks,hoy:now,vista:.siete).flatMap{$0.1}.count,1)
        XCTAssertEqual(VistaTareas.grupos(tasks,hoy:now,vista:.todo).flatMap{$0.1}.count,2)
    }
}
