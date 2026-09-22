import XCTest
import AppKit
@testable import SFMap

final class EditorTextoTests: XCTestCase {
    func testTextoVisibleDesdePrimerCaracterConSuAlineacion() {
        for alineacion in ["left", "center", "right"] {
            let editor = crear(tipo: "text", alineacion: alineacion)
            let scroll = editor.subviews.first as! NSScrollView
            let campo = scroll.documentView as! NSTextView
            XCTAssertEqual(campo.bounds.width, scroll.contentSize.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(campo.bounds.height, scroll.contentSize.height)
            campo.insertText("Hola", replacementRange: NSRange(location: 0, length: 0))
            let lm = campo.layoutManager!, tc = campo.textContainer!
            lm.ensureLayout(for: tc)
            let glifos = lm.boundingRect(forGlyphRange: lm.glyphRange(for: tc), in: tc)
            XCTAssertGreaterThan(glifos.width, 0)
            XCTAssertTrue(campo.visibleRect.intersects(glifos.offsetBy(dx: campo.textContainerOrigin.x, dy: campo.textContainerOrigin.y)))
            XCTAssertEqual(campo.textContainerInset.height, 0, "El texto libre no se centra al teclear")
            let estilo = campo.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(estilo?.alignment, alineacion == "center" ? .center : alineacion == "right" ? .right : .left)
            if alineacion == "center" { XCTAssertEqual(glifos.midX, tc.containerSize.width / 2, accuracy: 2) }
            if alineacion == "right" { XCTAssertEqual(glifos.maxX, tc.containerSize.width, accuracy: 2) }
        }
    }

    func testCodigoNoSeCentraAlEscribirYFiguraSi() {
        for tipo in ["code", "shape"] {
            let editor = crear(tipo: tipo, alineacion: "center", alto: 160)
            let campo = (editor.subviews.first as! NSScrollView).documentView as! NSTextView
            campo.insertText("Hola", replacementRange: NSRange(location: 0, length: 0))
            if tipo == "code" { XCTAssertEqual(campo.textContainerInset.height, 0) }
            else { XCTAssertGreaterThan(campo.textContainerInset.height, 20) }
        }
    }

    func testInsercionRealEnVentana() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let e = Crear.texto(.zero, z: 1, maxAncho: 420)
        let editor = EditorTexto(elemento: e, tema: .claro, camara: Camara(x: 0, y: 0, zoom: 1),
                                 viewport: NSSize(width: 800, height: 600), guardar: { _ in }, cancelar: {})
        window.contentView!.addSubview(editor)
        editor.enfocar()
        let campo = window.firstResponder as! NSTextView
        for letra in "Hola mundo" {
            campo.insertText(String(letra), replacementRange: campo.selectedRange())
            let lm = campo.layoutManager!, tc = campo.textContainer!
            lm.ensureLayout(for: tc)
            let r = lm.boundingRect(forGlyphRange: lm.glyphRange(for: tc), in: tc)
                .offsetBy(dx: campo.textContainerOrigin.x, dy: campo.textContainerOrigin.y)
            XCTAssertTrue(campo.visibleRect.intersects(r), "Invisible: \(campo.string), glifos=\(r), visible=\(campo.visibleRect)")
            XCTAssertGreaterThan(campo.bounds.width, 100)
        }

    }

    func testGestoDeInsercionYTecladoEnLienzoConZoom() {
        for zoom in [0.4, 1.0, 2.0, 3.0] {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            let lienzo = Lienzo(frame: window.contentView!.bounds)
            window.contentView!.addSubview(lienzo)
            lienzo.camara = Camara(x: 0, y: 0, zoom: zoom)
            lienzo.herramienta = .texto
            let punto = lienzo.convert(NSPoint(x: 200, y: 300), to: nil)
            for tipo in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let evento = NSEvent.mouseEvent(with: tipo, location: punto, modifierFlags: [], timestamp: 1,
                                                windowNumber: window.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1)!
                if tipo == .leftMouseDown { lienzo.mouseDown(with: evento) }
                else { lienzo.mouseUp(with: evento) }
            }
            guard let campo = window.firstResponder as? NSTextView else { XCTFail("No abrió editor"); continue }
            let lm = campo.layoutManager!, tc = campo.textContainer!
            lm.ensureLayout(for: tc)
            let cursor = campo.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            let centro = window.convertPoint(toScreen: campo.convert(NSPoint(x: campo.bounds.midX, y: 0), to: nil)).x
            XCTAssertEqual(cursor.minX, centro, accuracy: 2, "Cursor inicial centrado a zoom \(zoom)")
            for letra in "Texto visible" {
                let evento = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                             windowNumber: window.windowNumber, context: nil, characters: String(letra),
                                             charactersIgnoringModifiers: String(letra), isARepeat: false, keyCode: 0)!
                campo.keyDown(with: evento)
                lm.ensureLayout(for: tc)
                let r = lm.boundingRect(forGlyphRange: lm.glyphRange(for: tc), in: tc)
                    .offsetBy(dx: campo.textContainerOrigin.x, dy: campo.textContainerOrigin.y)
                XCTAssertTrue(campo.visibleRect.contains(r), "Glifos recortados a zoom \(zoom): \(r) visible \(campo.visibleRect)")
            }
            XCTAssertEqual(campo.string, "Texto visible")
            campo.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            XCTAssertEqual(lienzo.doc.elementos.first?.textoLibre, "Texto visible")
            XCTAssertTrue(window.firstResponder === lienzo, "Al confirmar vuelve el teclado al lienzo")
            let borrar = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                                         windowNumber: window.windowNumber, context: nil, characters: "\u{7f}",
                                         charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
            window.firstResponder?.keyDown(with: borrar)
            XCTAssertTrue(lienzo.doc.elementos.isEmpty, "Suprimir borra el objeto recién confirmado")
        }
    }

    func testColorSeleccionYBorradoEnAmbosTemas() throws {
        for tema in [Tema.claro, Tema.oscuro] {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: tema.nombre == "oscuro" ? .darkAqua : .aqua)
            let editor = EditorTexto(elemento: Crear.texto(.zero, z: 1, maxAncho: 300), tema: tema,
                                     camara: Camara(x: 0, y: 0, zoom: 1), viewport: window.contentView!.bounds.size,
                                     guardar: { _ in }, cancelar: {})
            window.contentView!.addSubview(editor)
            editor.enfocar()
            let campo = try XCTUnwrap(window.firstResponder as? NSTextView)
            XCTAssertFalse(campo.usesAdaptiveColorMappingForDarkAppearance, "El tema ya eligió el color: AppKit no debe invertirlo")
            campo.insertText("Texto legible", replacementRange: NSRange(location: 0, length: 0))
            campo.selectAll(nil)
            XCTAssertEqual(campo.selectedRange().length, campo.string.utf16.count)
            campo.deleteBackward(nil)
            XCTAssertEqual(campo.string, "")
            campo.insertText("Otra vez", replacementRange: NSRange(location: 0, length: 0))
            let color = try XCTUnwrap(campo.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(color.usingColorSpace(.sRGB), tema.tituloTexto.usingColorSpace(.sRGB))
            let punto = campo.convert(NSPoint(x: 10, y: 10), to: window.contentView)
            XCTAssertTrue(window.contentView?.hitTest(punto) === campo, "El ratón llega al texto")
        }
    }

    func testCambiarTemaMientrasEscribesConservaTextoSeleccionYContraste() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let lienzo = Lienzo(frame: window.contentView!.bounds)
        window.contentView!.addSubview(lienzo)
        let e = Crear.texto(.zero, z: 1, maxAncho: 300)
        lienzo.doc.cargar([e])
        lienzo.editarTexto(e.id)
        let campo = try XCTUnwrap(window.firstResponder as? NSTextView)
        campo.insertText("Sin desaparecer", replacementRange: NSRange(location: 0, length: 0))
        campo.setSelectedRange(NSRange(location: 0, length: 3))
        for tema in [Tema.oscuro, Tema.claro] {
            lienzo.tema = tema
            let color = try XCTUnwrap(campo.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(color.usingColorSpace(.sRGB), tema.tituloTexto.usingColorSpace(.sRGB))
            XCTAssertEqual(campo.selectedRange(), NSRange(location: 0, length: 3))
            XCTAssertEqual(campo.string, "Sin desaparecer")
            XCTAssertTrue(window.firstResponder === campo)
        }
    }

    func testDeshacerDelMenuActuaSobreElTextoActivo() throws {
        _ = NSApplication.shared
        let delegado = Delegado()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        delegado.ventana = window
        window.contentView!.addSubview(delegado.lienzo)
        let e = Crear.texto(.zero, z: 1, maxAncho: 300)
        delegado.lienzo.doc.agregar([e], etiqueta: "crear")
        delegado.lienzo.editarTexto(e.id)
        let campo = try XCTUnwrap(window.firstResponder as? NSTextView)
        campo.insertText("Texto", replacementRange: NSRange(location: 0, length: 0))
        campo.breakUndoCoalescing()
        delegado.perform(NSSelectorFromString("deshacerMenu"))
        XCTAssertEqual(campo.string, "")
        XCTAssertEqual(delegado.lienzo.doc.elementos.count, 1, "Deshacer texto no borra el objeto")
        delegado.perform(NSSelectorFromString("rehacerMenu"))
        XCTAssertEqual(campo.string, "Texto")
    }

    func testZoomPanYVentanaMientrasSeEscribe() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let lienzo = Lienzo(frame: window.contentView!.bounds)
        window.contentView!.addSubview(lienzo)
        let e = Crear.texto(CGPoint(x: -150, y: -30), z: 1, maxAncho: 300)
        lienzo.doc.cargar([e]); lienzo.doc.seleccion = [e.id]
        lienzo.camara = Camara(x: 0, y: 0, zoom: 1)
        let barra = BarraContextual(frame: .zero)
        window.contentView!.addSubview(barra)
        lienzo.editarTexto(e.id)
        let campo = try XCTUnwrap(window.firstResponder as? NSTextView)
        let editor = try XCTUnwrap(window.contentView!.subviews.compactMap { $0 as? EditorTexto }.first)
        campo.insertText("Escribiendo en el lienzo", replacementRange: NSRange(location: 0, length: 0))
        campo.setSelectedRange(NSRange(location: 0, length: 3))
        for zoom in [2.0, 0.4, 3.0, 1.0] {
            lienzo.camara = Camara(x: 25, y: -15, zoom: zoom)
            let marco = editor.frame
            XCTAssertEqual(marco.minX, (e.x - 25) * zoom + lienzo.bounds.width / 2, accuracy: 0.1)
            XCTAssertEqual(marco.maxY, lienzo.bounds.height / 2 - (e.y + 15) * zoom, accuracy: 0.1)
            XCTAssertEqual(marco.width, e.ancho * zoom, accuracy: 0.1)
            XCTAssertEqual(campo.convert(CGRect(x: 0, y: 0, width: 10, height: 10), to: window.contentView).width, 10 * zoom, accuracy: 0.1)
            XCTAssertTrue(window.firstResponder === campo)
            XCTAssertEqual(campo.selectedRange(), NSRange(location: 0, length: 3))
            XCTAssertEqual(campo.string, "Escribiendo en el lienzo")
        }
        lienzo.setFrameSize(NSSize(width: 900, height: 550))
        XCTAssertEqual(editor.frame.minX, e.x - 25 + 450, accuracy: 0.1)
        XCTAssertEqual(editor.frame.maxY, 275 - (e.y + 15), accuracy: 0.1)
        for tema in [Tema.claro, Tema.oscuro] {
            lienzo.tema = tema; barra.tema = tema; barra.seleccion = [e]
            barra.reconstruir(caja: e.caja, camara: lienzo.camara, viewport: lienzo.bounds.size)
            XCTAssertGreaterThan(barra.frame.minY, editor.frame.maxY)
            XCTAssertLessThan(barra.frame.width, 410)
            if let directorio = ProcessInfo.processInfo.environment["SFMAP_EDITOR_FOTOS"] {
                campo.setSelectedRange(NSRange(location: campo.string.utf16.count, length: 0))
                let raiz = window.contentView!
                let bitmap = try XCTUnwrap(raiz.bitmapImageRepForCachingDisplay(in: raiz.bounds))
                raiz.cacheDisplay(in: raiz.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to:
                    URL(fileURLWithPath: directorio).appendingPathComponent("sfmap-texto-\(tema.nombre).png"))
            }
        }
    }

    func testTextoTieneAgarresVisiblesSinTiradorSobreLaBarra() {
        let r = CGRect(x: 0, y: 0, width: 300, height: 40)
        XCTAssertNil(Geo.manijaEn(r, Geo.centroGiro(r, zoom: 1), zoom: 1, texto: true))
        XCTAssertNil(Geo.manijaEn(r, Geo.centroManija(r, "n"), zoom: 1, texto: true))
        for h in ["nw", "ne", "e", "se", "sw", "w"] {
            XCTAssertEqual(Geo.manijaEn(r, Geo.centroManija(r, h), zoom: 1, texto: true), h)
        }
    }

    private func crear(tipo: String, alineacion: String, alto: Double = 40) -> EditorTexto {
        _ = NSApplication.shared
        let e = Elemento(.objeto(["id": .texto("prueba"), "type": .texto(tipo),
            "x": .numero(0), "y": .numero(0), "width": .numero(420), "height": .numero(alto),
            "text": .texto(""), "textAlign": .texto(alineacion)]))
        return EditorTexto(elemento: e, tema: .claro, camara: Camara(x: 0, y: 0, zoom: 1),
                           viewport: NSSize(width: 800, height: 600), guardar: { _ in }, cancelar: {})
    }
}
