// NUCLEO COMPARTIDO — lo compilan sfcal y sfmap (enlace simbólico).
//
// ⌘R QUE DE VERDAD RECARGA. Daniel, 25 ago: *"hice cmd + R y no vi el filtro
// aplicado, me tocó cerrar y abrir la app… estas mejoras se aplican tan fácil
// como un cmd + r sin tener que cerrar y abrir la app"*.
//
// Tenía razón en la queja y la causa era doble: ⌘R refrescaba el DATO remoto
// pero no releía el estado local (el filtro vive en un archivo), y sobre todo
// no podía adoptar un BINARIO NUEVO — para eso hay que relanzar, y eso lo hacía
// él a mano cada vez que yo instalaba algo.

import AppKit

/// Adoptar la versión recién instalada sin que el usuario cierre nada.
///
/// ⚠️ POR QUÉ ESTO NO ES UN CAPRICHO. Estas dos apps se reinstalan varias veces
/// al día mientras se trabaja en ellas. Cada instalación dejaba al proceso vivo
/// corriendo el binario ANTERIOR: la app seguía funcionando, no fallaba nada, y
/// simplemente no tenía lo nuevo. Daniel pulsaba ⌘R, no veía el cambio, y tenía
/// que descubrir por su cuenta que había que relanzar. Un fallo mudo más.
enum Relanzar {

    /**
     * Cuándo arrancó ESTE proceso, PREGUNTÁNDOSELO AL KERNEL.
     *
     * ⚠️ La primera versión era `static let arranque = Date()`, y no funcionó
     * nunca: en Swift un `static let` es PEREZOSO — se inicializa la primera
     * vez que alguien lo toca, y el primero que lo tocaba era… el propio ⌘R.
     * Así que `arranque` acababa siendo el instante del atajo, el binario nuevo
     * jamás era "más nuevo que el arranque", y la comprobación devolvía false
     * en silencio. Daniel: *"el widget no me está redireccionando, ninguno"* —
     * y era esto: seguía corriendo el binario viejo creyendo que ⌘R lo había
     * actualizado.
     *
     * `kinfo_proc.kp_proc.p_starttime` es el dato de verdad y no se puede
     * despistar: lo pone el kernel cuando nace el proceso.
     */
    static var arranque: Date = {
        var info = kinfo_proc()
        var tam = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &tam, nil, 0) == 0 else {
            // Sin el dato del kernel, se asume que hace mucho: mejor ofrecer un
            // relanzado de más que quedarse con un binario viejo sin avisar.
            return Date(timeIntervalSince1970: 0)
        }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1e6)
    }()

    /// ¿Hay una versión instalada más nueva que la que corre?
    ///
    /// Se compara con el ejecutable y no con el `.app`: al reemplazar el bundle,
    /// el proceso vivo conserva su inodo viejo y la RUTA ya apunta al nuevo.
    static func hayVersionNueva() -> Bool {
        guard let exe = Bundle.main.executableURL,
              let m = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date
        else { return false }
        // Margen de 2 s: el proceso arranca unas décimas después de que el
        // instalador toque el archivo, y sin margen la app se relanzaría a sí
        // misma en bucle nada más abrir.
        return m > arranque.addingTimeInterval(2)
    }

    /// Relanza la app y cierra esta instancia. Devuelve `false` si no había nada
    /// que adoptar (y entonces quien llama debe refrescar los datos y ya).
    @discardableResult
    static func siHayVersionNueva() -> Bool {
        guard hayVersionNueva() else { return false }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            // El terminate va DESPUÉS de que la nueva instancia haya arrancado:
            // al revés, macOS puede reusar el proceso que se está muriendo y el
            // usuario se queda sin ventana. (Y con un pequeño respiro, porque
            // el callback llega antes de que la nueva pinte.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
        }
        return true
    }
}
