import AppKit

enum VistaTareas: String, CaseIterable {
    case hoy, siete, todo
    var titulo: String { switch self { case .hoy: return "Hoy"; case .siete: return "7 días"; case .todo: return "Todo" } }
    static var elegida: VistaTareas {
        get { VistaTareas(rawValue: UserDefaults.standard.string(forKey:"sfmap.vistaTareas") ?? "") ?? .hoy }
        set { UserDefaults.standard.set(newValue.rawValue,forKey:"sfmap.vistaTareas") }
    }
    nonisolated(unsafe) static var hechosAbiertos = false
    nonisolated(unsafe) static var backlogAbierto = false
    nonisolated(unsafe) static var controles: [(String,CGRect)] = []
    static func grupos(_ ts:[TareaDia], hoy:Date, vista:VistaTareas) -> [(String,[TareaDia])] {
        let fecha=GDate.formatDay(hoy), fin=GDate.formatDay(DateKit.addDays(hoy,6))
        let vivos=ts.filter { !Pintor.cerradas.contains($0.id) }
        let orden: (TareaDia,TareaDia)->Bool = { ($0.prioridad,$0.hora ?? "",$0.contenido) < ($1.prioridad,$1.hora ?? "",$1.contenido) }
        if vista == .hoy {
            return [("En curso",vivos.filter{$0.estado == "Haciendo"}.sorted(by:orden)),
                    ("Vencidas",vivos.filter{$0.estado != "Haciendo" && $0.dia != nil && $0.dia! < fecha}.sorted(by:orden)),
                    ("Hoy",vivos.filter{$0.estado != "Haciendo" && $0.dia == fecha}.sorted(by:orden))]
        }
        let fechadas=vivos.filter { $0.dia != nil && (vista == .todo || $0.dia! <= fin) }
        return Dictionary(grouping:fechadas,by:{$0.dia!}).keys.sorted().map { d in
            (d == fecha ? "Hoy" : d < fecha ? "Vencidas · "+d : d, fechadas.filter{$0.dia == d}.sorted(by:orden))
        }
    }
}

extension Pintor {
    func widgetTareas(_ r:CGRect) {
        Self.casillasTarea.removeAll(keepingCapacity:true)
        VistaTareas.controles.removeAll(keepingCapacity:true)
        let pad=Self.wPad
        var y=wCabeceraDe(r,rotulo:"tareas · vía Todoist",sub:nil,alDia:dia.tareas.alDia,vara:Cronista.varaTareas,fallo:dia.tareas.fallo)
        for (i,v) in VistaTareas.allCases.enumerated() {
            let b=CGRect(x:r.minX+pad+Double(i)*105,y:y,width:95,height:32)
            VistaTareas.controles.append((v.rawValue,b))
            wCaja(b,radio:6,relleno:v == VistaTareas.elegida ? tema.acento : tema.rol("card").relleno,trazo:tema.reticula)
            wTexto(v.titulo,CGPoint(x:b.minX+15,y:b.minY+6),tam:17,peso:700,color:v == VistaTareas.elegida ? .white : tema.tituloTexto)
        }
        y += 52
        guard let todas=dia.tareas.valor else { return }
        let tareas=todas.filter{dia.filtro.deja(frente:$0.frenteId,prioridad:$0.prioridad,etiquetas:$0.etiquetas,dia:$0.dia)}
        let ocultas=todas.count-tareas.count
        if ocultas > 0 {wTexto("Filtro de sfcal · \(ocultas) ocultas",CGPoint(x:r.minX+pad,y:y),tam:14,peso:600,color:tema.pieTexto);y += 28}
        let soloBacklog = VistaTareas.elegida == .todo && VistaTareas.backlogAbierto
        let grupos = soloBacklog ? [] : VistaTareas.grupos(tareas,hoy:Date(),vista:VistaTareas.elegida)
        let fila = VistaTareas.elegida == .todo ? 62.0 : 82.0
        let total=grupos.reduce(0){$0+$1.1.count}
        let fondo=r.maxY-pad-90
        var pintadas=0
        for (nombre,lista) in grupos where !lista.isEmpty {
            guard y+fila+26 < fondo else {break}
            wTexto(nombre.uppercased()+" · \(lista.count)",CGPoint(x:r.minX+pad,y:y),tam:16,peso:800,color:tema.acento)
            y += 26
            for original in lista {
                guard y+fila <= fondo else {break}
                var t=original
                if t.contenido.hasPrefix("Curso N4 Business OS:") { t.contenido="Preparar contenido del curso N4 Business OS" }
                filaTarea(t,CGRect(x:r.minX+pad,y:y,width:r.width-2*pad,height:fila),urgente:nombre.hasPrefix("Vencidas"))
                y += fila;pintadas += 1
            }
            y += 6
        }
        if total == 0 && !soloBacklog {wTexto(VistaTareas.elegida == .hoy ? "Sin tareas pendientes para hoy." : "Sin tareas en este horizonte.",CGPoint(x:r.minX+pad,y:y),tam:19,peso:600,color:tema.tituloTexto);y += 40}
        if pintadas < total {wTexto("\(total-pintadas) más · abrir lista completa en sfcal",CGPoint(x:r.minX+pad,y:y),tam:14,peso:600,color:tema.pieTexto);y += 30}
        if VistaTareas.elegida == .todo {
            let back=tareas.filter{$0.dia == nil}
            let b=CGRect(x:r.minX+pad,y:min(y,fondo),width:r.width-2*pad,height:30)
            VistaTareas.controles.append(("backlog",b))
            wTexto("\(VistaTareas.backlogAbierto ? "▾" : "▸") Backlog · \(back.count)",CGPoint(x:b.minX,y:b.minY),tam:16,peso:700,color:tema.pieTexto)
            y=b.maxY+8
            if VistaTareas.backlogAbierto {for t in back {guard y+27 < r.maxY-pad else {break};wTexto(wCortar(t.contenido,ancho:r.width-2*pad,tam:15,peso:500),CGPoint(x:r.minX+pad,y:y),tam:15,peso:500,color:tema.cuerpoTexto);y += 27}}
        } else if VistaTareas.elegida == .hoy {
            let fecha=GDate.formatDay(Date())
            let hechos=(dia.completadas.valor ?? []).filter{$0.dia == fecha}
            let b=CGRect(x:r.minX+pad,y:min(y,fondo),width:r.width-2*pad,height:30)
            VistaTareas.controles.append(("hechos",b))
            let cuenta=dia.completadas.valor == nil ? "sin lectura" : "\(hechos.count)"
            wTexto("\(VistaTareas.hechosAbiertos ? "▾" : "▸") Hecho hoy · \(cuenta)",CGPoint(x:b.minX,y:b.minY),tam:16,peso:700,color:tema.pieTexto)
            y=b.maxY+8
            if VistaTareas.hechosAbiertos {for t in hechos {guard y+27 < r.maxY-pad else {break};wTexto(wCortar("✓ "+t.contenido,ancho:r.width-2*pad,tam:15,peso:500),CGPoint(x:r.minX+pad,y:y),tam:15,peso:500,color:tema.cuerpoTexto);y += 27}}
        }
    }
}
