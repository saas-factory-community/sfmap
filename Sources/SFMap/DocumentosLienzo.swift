import AppKit

/// Preferencia local: el lienzo empieza sin paneles que se abren al pulsar.
enum DocumentosLienzo {
    static let clave = "sfmap.documentosActivos"
    static func leer(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: clave) }
    static func guardar(_ activos: Bool, en defaults: UserDefaults = .standard) { defaults.set(activos, forKey: clave) }
    static func permite(_ liga: String?, activos: Bool) -> Bool {
        guard let liga else { return false }
        if case .documento = Enlace.leer(liga) { return activos }
        return true
    }
}

extension Icono {
    static let documentos = dibujar { c, _ in
        c.move(to: CGPoint(x: 7, y: 3)); c.addLine(to: CGPoint(x: 14, y: 3))
        c.addLine(to: CGPoint(x: 19, y: 8)); c.addLine(to: CGPoint(x: 19, y: 21))
        c.addLine(to: CGPoint(x: 7, y: 21)); c.closePath(); c.strokePath()
        c.move(to: CGPoint(x: 14, y: 3)); c.addLine(to: CGPoint(x: 14, y: 8))
        c.addLine(to: CGPoint(x: 19, y: 8)); c.strokePath()
        for y in [12.0, 16.0] {
            c.move(to: CGPoint(x: 10, y: y)); c.addLine(to: CGPoint(x: 16, y: y)); c.strokePath()
        }
    }
}
