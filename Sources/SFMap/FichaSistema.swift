import Foundation

/// Evidencia y decisión pertenecen al elemento, no a una copia del expediente.
/// Campos aditivos: las demás superficies los conservan aunque no los pinten.
enum FichaSistema {
    static func tiene(_ e: Elemento) -> Bool {
        e.crudo["relation"] != nil || e.crudo["evidence"] != nil || e.crudo["decision"] != nil
    }

    static func markdown(_ e: Elemento, elementos: [Elemento]) -> String {
        func nombre(_ id: String?) -> String {
            guard let id, let n=elementos.first(where:{$0.id==id}) else { return id ?? "Sin nodo" }
            return n.crudo["name"]?.s ?? n.titulo ?? n.textoLibre ?? n.textoLigado?.first?.texto ?? id
        }
        func estado(_ s: String?) -> String {
            switch s {
            case "observed": return "Observado"
            case "declared": return "Declarado por su autor"
            case "proposed": return "Propuesto; no implementado"
            case "inferred": return "Inferido; por verificar"
            default: return "Sin verificar"
            }
        }
        var partes=["# \(e.crudo["name"]?.s ?? e.etiqueta ?? nombre(e.id))"]
        if let r=e.crudo["relation"] {
            partes += ["**\(nombre(e.desdeId)) → \(nombre(e.hastaId))**",r["action"]?.s ?? e.etiqueta ?? "Relación sin acción documentada",
                       "Estado: \(estado(r["status"]?.s))"]
            if let c=r["condition"]?.s { partes.append("Condición: \(c)") }
            if let desde=e.desdeId { partes.append("[Ver origen](node:\(desde)) · [Ver destino](node:\(e.hastaId ?? desde))") }
        }
        let fuentes=(e.crudo["evidence"]?.arr ?? [])+(e.crudo["relation"]?["evidence"]?.arr ?? [])
        if !fuentes.isEmpty {
            partes.append("## Evidencia")
            for f in fuentes {
                let rotulo=f["title"]?.s ?? "Fuente"
                let link=f["url"]?.s
                partes.append("- \(link.map { "[\(rotulo)](\($0))" } ?? rotulo) · \(f["date"]?.s ?? "sin fecha") · \(estado(f["status"]?.s))")
            }
        } else { partes.append("Sin evidencia adjunta. La conexión por sí sola no prueba el recorrido.") }
        if let d=e.crudo["decision"] {
            partes.append("## Decisión")
            for (k,n) in [("question","Pregunta"),("hypothesis","Hipótesis"),("change","Cambio propuesto"),("measure","Cómo comprobarlo"),("status","Estado"),("result","Resultado")] {
                if let s=d[k]?.s { partes.append("**\(n):** \(s)") }
            }
            if d["result"]?.s == nil { partes.append("Resultado: todavía no medido.") }
        }
        if let s=e.crudo["note"]?.s { partes.append(s) }
        return partes.joined(separator:"\n\n")
    }
}
