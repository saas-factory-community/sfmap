import XCTest
@testable import SFMap

/// LOS EJES — donde una gráfica miente.
///
/// Una curva sin escala se lee como uno quiera: la misma serie parece un
/// desplome o un temblor según cuánto zoom tenga el eje Y. Y los errores de
/// escala no se ven —la gráfica sale bonita y dice otra cosa—, así que la
/// aritmética se prueba con números o no se prueba.
final class EjesTests: XCTestCase {

    // ── el eje Y ────────────────────────────────────────────────────────────

    /// ⭐ NÚMEROS REDONDOS, no los que salgan. "8.200 → 9.400" no dice nada;
    /// "8.500 · 9.000 · 9.500" se compara de un vistazo con cualquier lectura.
    func testLasMarcasSonNumerosRedondos() {
        let e = Ejes.escalaY([8220, 8299, 9074, 9157])
        XCTAssertTrue([100.0, 200, 250, 500].contains(e.paso), "paso poco redondo: \(e.paso)")
        for m in e.marcas {
            XCTAssertEqual((m / e.paso).rounded(), m / e.paso, accuracy: 1e-6,
                           "\(m) no es múltiplo del paso")
        }
        XCTAssertLessThanOrEqual(e.lo, 8220, "el suelo tiene que contener el mínimo")
        XCTAssertGreaterThanOrEqual(e.hi, 9157, "el techo tiene que contener el máximo")
    }

    func testLaEscalaContieneSiempreLaSerie() {
        for serie in [[0.0, 1], [-5.0, 3], [8220.0, 8221], [0.02, 0.09], [1e6, 1.2e6]] {
            let e = Ejes.escalaY(serie)
            XCTAssertLessThanOrEqual(e.lo, serie.min()!, "la escala corta el mínimo")
            XCTAssertGreaterThanOrEqual(e.hi, serie.max()!, "la escala corta el máximo")
            XCTAssertGreaterThan(e.marcas.count, 1)
            XCTAssertLessThan(e.marcas.count, 13, "más de doce marcas es una mancha")
        }
    }

    /// ⚠️ SERIE PLANA ≠ RANGO CERO. Sin margen, la división por rango explota y
    /// la línea se pinta pegada a un borde: "no pasó nada" se leería como un
    /// mínimo histórico.
    func testUnaSeriePlanaNoRompeLaEscala() {
        let e = Ejes.escalaY([437, 437, 437])
        XCTAssertGreaterThan(e.hi - e.lo, 0, "rango cero: la gráfica se pintaría contra un borde")
        XCTAssertEqual(e.fraccion(437), 0.5, accuracy: 0.35, "el valor único queda dentro")
        XCTAssertFalse(e.fraccion(437).isNaN)
    }

    /// La fracción es la que posiciona el punto: si se sale de 0…1, la línea se
    /// pinta fuera de su caja.
    func testLaFraccionSeQuedaDentro() {
        let vs = [8220.0, 8299, 9074]
        let e = Ejes.escalaY(vs)
        for v in vs {
            XCTAssertGreaterThanOrEqual(e.fraccion(v), 0)
            XCTAssertLessThanOrEqual(e.fraccion(v), 1)
        }
    }

    /// Los decimales los manda el PASO. Con paso 20 sobra el ".0"; con paso 0.5
    /// hace falta un decimal o dos marcas seguidas dirían lo mismo.
    func testLosDecimalesLosMandaElPaso() {
        XCTAssertEqual(Ejes.rotuloY(8200, paso: 100, moneda: true), "$8,200")
        XCTAssertEqual(Ejes.rotuloY(-3, paso: 1, moneda: false), "−3")
        XCTAssertEqual(Ejes.rotuloY(0, paso: 1, moneda: false), "0")
        XCTAssertEqual(Ejes.rotuloY(0.5, paso: 0.5, moneda: false), "0.5")
        XCTAssertEqual(Ejes.rotuloY(12000, paso: 1000, moneda: true), "$12.0k",
                       "cinco dígitos por marca se comen el ancho de la gráfica")
    }

    /// −0.0 existe en coma flotante y se pintaría como "-0".
    func testElCeroNegativoNoSePinta() {
        let e = Ejes.escalaY([-3.0, 1])
        for m in e.marcas where abs(m) < 1e-9 {
            XCTAssertFalse(Ejes.rotuloY(m, paso: e.paso, moneda: false).hasPrefix("−"))
        }
    }

    // ── el eje X ────────────────────────────────────────────────────────────

    private func dias(_ n: Int, desde: String = "2026-08-18") -> [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let d0 = f.date(from: desde)!
        return (0..<n).map { f.string(from: Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: $0, to: d0)!) }
    }

    /// ⭐ Lo que pidió Daniel, literal: *"para el filtro de 7 días, en el eje X
    /// divide por 7 segmentos"*.
    func testSieteDiasSonSieteMarcas() {
        let m = Ejes.marcasX(fechas: dias(7), dias: 7, anchoDisponible: 700)
        XCTAssertEqual(m.count, 7, "la ventana de 7 días lleva una marca por día")
        XCTAssertEqual(m.first?.rotulo, "18 ago")
        XCTAssertEqual(m.last?.rotulo, "24 ago")
    }

    /// 30 y 90 días no llevan una marca por día: 90 rótulos en 700 px son una
    /// mancha negra. Se rebaja a una por semana / por mes.
    func testLasVentanasLargasSeRalean() {
        let m30 = Ejes.marcasX(fechas: dias(30, desde: "2026-07-26"), dias: 30, anchoDisponible: 700)
        XCTAssertGreaterThanOrEqual(m30.count, 3)
        XCTAssertLessThanOrEqual(m30.count, 6, "una marca por semana, no por día")
        let m90 = Ejes.marcasX(fechas: dias(90, desde: "2026-05-29"), dias: 90, anchoDisponible: 700)
        XCTAssertLessThanOrEqual(m90.count, 5, "una marca por mes")
    }

    /// ⚠️ Y hay un tope por ANCHO: un eje cuyos rótulos se pisan miente sobre
    /// dónde está cada punto.
    func testSiNoCabenSeRaleanMas() {
        let estrecho = Ejes.marcasX(fechas: dias(7), dias: 7, anchoDisponible: 120)
        XCTAssertLessThan(estrecho.count, 7, "en 120 px no caben siete rótulos")
        XCTAssertGreaterThanOrEqual(estrecho.count, 2, "…pero los extremos siempre")
    }

    /// Los extremos anclan la lectura: sin ellos no se sabe de cuándo a cuándo.
    func testLosExtremosSiempreEstan() {
        let f = dias(30, desde: "2026-07-26")
        let m = Ejes.marcasX(fechas: f, dias: 30, anchoDisponible: 700)
        XCTAssertEqual(m.first?.indice, 0)
        XCTAssertEqual(m.last?.indice, f.count - 1)
    }

    func testLosIndicesSonValidosYCrecientes() {
        let f = dias(30, desde: "2026-07-26")
        let m = Ejes.marcasX(fechas: f, dias: 30, anchoDisponible: 700)
        for x in m { XCTAssertTrue(f.indices.contains(x.indice), "índice fuera de la serie") }
        XCTAssertEqual(m.map(\.indice), m.map(\.indice).sorted(), "el eje va hacia delante")
        XCTAssertEqual(Set(m.map(\.indice)).count, m.count, "dos marcas en el mismo punto")
    }

    func testUnaSerieDeUnPuntoNoTieneEje() {
        XCTAssertTrue(Ejes.marcasX(fechas: ["2026-08-24"], dias: 7, anchoDisponible: 700).isEmpty)
        XCTAssertTrue(Ejes.marcasX(fechas: [], dias: 7, anchoDisponible: 700).isEmpty)
    }

    func testLaFechaCortaSeLee() {
        XCTAssertEqual(Ejes.diaCorto("2026-08-24"), "24 ago")
        XCTAssertEqual(Ejes.diaCorto("2026-01-01"), "1 ene")
        XCTAssertNil(Ejes.diaCorto("2026-13-01"), "un mes 13 no se pinta")
        XCTAssertNil(Ejes.diaCorto("basura"))
    }
}
