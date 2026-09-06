// Rasteriza assets/logo.svg a un .icns completo.
//
// Usa WebKit en vez de rsvg/imagemagick a proposito: WebKit SIEMPRE esta en
// macOS, asi que el icono se puede regenerar en cualquier maquina de Daniel sin
// instalar nada. Y es el MISMO motor que pintara el SVG en cualquier otro sitio,
// asi que lo que se ve aqui es lo que se ve en todos lados.
import AppKit
import WebKit

let raiz = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let svg = raiz.appendingPathComponent("assets/logo.svg")
// ⚠️ EL SVG SE CARGA DENTRO DE UN HTML QUE LO ESCALA.
//
// Cargarlo directo salia RECORTADO: el SVG declara width/height de 1024 y
// WebKit respeta ese tamaño natural, asi que en un viewport de 256 solo cabe
// la esquina superior izquierda. El capture salia con un trozo del borde y
// nada del glifo — y se veia bien en el log ("✓ 256px") porque el rasterizador
// no puede saber que capturo basura.
let envoltura = raiz.appendingPathComponent(".sfmap-icono.html")
let salida = raiz.appendingPathComponent("assets/sfmap.iconset")
/// LA TABLA EXACTA de píxeles → nombres que `iconutil` reconoce.
///
/// Escrita a mano y no derivada de una fórmula: la primera versión calculaba el
/// nombre `@2x` dividiendo entre dos, y eso produce `icon_64x64@2x` (que
/// iconutil no acepta) mientras se salta `icon_32x32@2x` (que sí necesita, y
/// mide 64). Una regla que casi acierta es peor que una tabla de diez líneas.
let plan: [(px: Int, nombres: [String])] = [
    (16,   ["icon_16x16.png"]),
    (32,   ["icon_32x32.png", "icon_16x16@2x.png"]),
    (64,   ["icon_32x32@2x.png"]),
    (128,  ["icon_128x128.png"]),
    (256,  ["icon_256x256.png", "icon_128x128@2x.png"]),
    (512,  ["icon_512x512.png", "icon_256x256@2x.png"]),
    (1024, ["icon_512x512@2x.png"]),
]
let tamanos = plan.map(\.px)

final class Pintor: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var pendientes: [Int]
    let hecho: () -> Void
    init(pendientes: [Int], hecho: @escaping () -> Void) {
        self.web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        self.pendientes = pendientes
        self.hecho = hecho
        super.init()
        web.navigationDelegate = self
        // Fondo transparente: el propio SVG pinta su teja, y un blanco de
        // WebKit por debajo se colaria en las esquinas redondeadas.
        web.setValue(false, forKey: "drawsBackground")
    }
    func webView(_ w: WKWebView, didFinish _: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.capturar() }
    }
    func capturar() {
        guard let lado = pendientes.first else { hecho(); return }
        pendientes.removeFirst()
        web.frame = NSRect(x: 0, y: 0, width: lado, height: lado)
        let cfg = WKSnapshotConfiguration()
        cfg.snapshotWidth = NSNumber(value: lado)
        web.takeSnapshot(with: cfg) { img, _ in
            /*
             * ⚠️ SE RE-MUESTREA A PÍXELES EXACTOS.
             *
             * `snapshotWidth` está en PUNTOS, y en una pantalla Retina la
             * captura vuelve al DOBLE en píxeles. El 20 ago 2026 eso produjo un
             * iconset entero mal etiquetado —`icon_128x128.png` medía 256 px—
             * y macOS, al no encontrar ninguno de los tamaños que busca, cayó
             * al icono genérico del Dock.
             *
             * Y el rasterizador imprimía "✓ 128px" igual: reportaba lo que
             * había PEDIDO, no lo que había salido. Por eso ahora la medida se
             * verifica sobre el bitmap escrito.
             */
            guard let img else { print("  ✗ \(lado)px: sin captura"); exit(1) }
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: lado, height: lado)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            img.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado),
                     from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("  ✗ \(lado)px: sin png"); exit(1)
            }
            let escritos = plan.first { $0.px == lado }?.nombres ?? []
            for n in escritos { try? png.write(to: salida.appendingPathComponent(n)) }

            // SE COMPRUEBA lo escrito, no lo pedido.
            let ok = escritos.allSatisfy { n in
                guard let r = NSImageRep(contentsOf: salida.appendingPathComponent(n)) else { return false }
                return r.pixelsWide == lado && r.pixelsHigh == lado
            }
            print(ok ? "  ✓ \(lado)px → \(escritos.joined(separator: ", "))"
                     : "  ✗ \(lado)px: el archivo NO mide \(lado)")
            if !ok { exit(1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.capturar() }
        }
    }
}

try? FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let pintor = Pintor(pendientes: tamanos) { print("LISTO"); exit(0) }
let ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                       styleMask: [.borderless], backing: .buffered, defer: false)
ventana.contentView = pintor.web
ventana.orderFrontRegardless()
let cuerpo = (try? String(contentsOf: svg, encoding: .utf8)) ?? ""
let html = """
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;background:transparent;overflow:hidden}
  svg{display:block;width:100vw;height:100vh}
</style>
\(cuerpo)
"""
try? html.write(to: envoltura, atomically: true, encoding: .utf8)
pintor.web.loadFileURL(envoltura, allowingReadAccessTo: raiz)
app.run()
