import AppKit
import CoreText

/// Las fuentes, cargadas de los MISMOS archivos que mide el compilador.
///
/// No es purismo: el compilador corta las líneas midiendo `Montserrat[wght].ttf`
/// con fontkit y guarda esas líneas en el documento. Si sfmap pintara con una
/// fuente parecida del sistema, el texto ocuparía otro ancho del que la caja
/// declara y el resultado se saldría o quedaría corto — sin que nada falle.
/// Un archivo, las mismas métricas, en las tres superficies.
enum Fuentes {
    private static var cache: [String: CTFont] = [:]
    private static var registradas = false
    /// Familias que NO se pudieron cargar. Se DICE, no se traga.
    private(set) static var faltantes: [String] = []

    private static let archivos: [String: String] = [
        "montserrat": "Montserrat[wght]",
        "roboto-slab": "RobotoSlab[wght]",
        "caveat": "Caveat[wght]",
        "jetbrains-mono": "JetBrainsMono[wght]",
        "cormorant": "CormorantGaramond[wght]",
        "cormorant-italic": "CormorantGaramond-Italic[wght]",
    ]

    static func registrar() {
        guard !registradas else { return }
        registradas = true
        for (id, archivo) in archivos {
            guard let url = urlDe(archivo) else { faltantes.append(id); continue }
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) {
                // Ya registrada no es un fallo: pasa al reabrir en la misma sesión.
                // 105 = alreadyRegistered. Reabrir en la misma sesion la
                // vuelve a registrar y eso NO es un fallo.
                let code = err.map { CFErrorGetCode($0.takeUnretainedValue()) } ?? 0
                if code != 105 { faltantes.append(id) }
            }
        }
    }

    /// Dónde está el .ttf.
    ///
    /// NO se usa `Bundle.module`: hace `fatalError` cuando el bundle de
    /// recursos no está, así que un empaquetado mal hecho no daría una fuente
    /// fea — daría un crash al abrir. Dentro del .app las fuentes viven en
    /// `Contents/Resources/fuentes`; en desarrollo, junto al código.
    private static func urlDe(_ archivo: String) -> URL? {
        if let u = Bundle.main.url(forResource: archivo, withExtension: "ttf", subdirectory: "fuentes") { return u }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/fuentes/\(archivo).ttf")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    private static let postscript: [String: String] = [
        "montserrat": "Montserrat-Regular",
        "roboto-slab": "RobotoSlab-Regular",
        "caveat": "Caveat-Regular",
        "jetbrains-mono": "JetBrainsMono-Regular",
        // La cara default del archivo variable de Cormorant es Light (300);
        // el peso real lo pone el eje wght igual que en las demás.
        "cormorant": "CormorantGaramond-Light",
    ]

    /// Una fuente al peso pedido, usando el EJE VARIABLE real.
    ///
    /// Pedir "Montserrat-Bold" por nombre no funciona con un archivo variable:
    /// hay una sola cara y el peso es una coordenada. Se abre la cara y se le
    /// aplica la variación `wght`, que es lo que hace el navegador.
    static func fuente(familia: String, peso: Double, tamano: Double, cursiva: Bool) -> CTFont {
        registrar()
        let llave = "\(familia)|\(Int(peso))|\(Int(tamano * 100))|\(cursiva)"
        if let f = cache[llave] { return f }

        let nombre: String
        if cursiva && familia == "montserrat" { nombre = "Montserrat-Italic" }
        else if cursiva && familia == "cormorant" { nombre = "CormorantGaramond-LightItalic" }
        else { nombre = postscript[familia] ?? "Montserrat-Regular" }
        var base = CTFontCreateWithName(nombre as CFString, tamano, nil)
        // Si el nombre no existe cae al sistema y la medida deja de valer: se
        // declara en vez de pintar algo parecido y callar.
        if (CTFontCopyPostScriptName(base) as String).hasPrefix(".") {
            if !faltantes.contains(familia) { faltantes.append(familia) }
            base = CTFontCreateWithName("HelveticaNeue" as CFString, tamano, nil)
        }
        let ejes = [kCTFontVariationAxisIdentifierKey: 0x77676874] // 'wght'
        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontVariationAttribute: [ejes[kCTFontVariationAxisIdentifierKey]!: peso],
        ] as CFDictionary)
        let f = CTFontCreateCopyWithAttributes(base, tamano, nil, desc)
        cache[llave] = f
        return f
    }
}
