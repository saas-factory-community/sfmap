import CoreGraphics

/// Una geometría compartida por pintura, agarre, etiquetas y exportación.
/// Las curvas antiguas conservan su cuadrática. `curveStyle: ports` crea una
/// cúbica que sale y entra perpendicularmente por los puertos declarados.
enum TrazoConector {
    static func controles(_ e: Elemento) -> (CGPoint, CGPoint)? {
        let p = e.ruta
        guard p.count == 2, e.ruteo == "curva", e.crudo["curveStyle"]?.s == "ports" else { return nil }
        let d = max(36, min(600, hypot(p[1].x-p[0].x, p[1].y-p[0].y) * 0.42))
        func salida(_ p: CGPoint, _ lado: String) -> CGPoint {
            switch lado {
            case "n": return CGPoint(x:p.x, y:p.y-d)
            case "s": return CGPoint(x:p.x, y:p.y+d)
            case "w": return CGPoint(x:p.x-d, y:p.y)
            default: return CGPoint(x:p.x+d, y:p.y)
            }
        }
        return (salida(p[0], e.crudo["fromPort"]?.s ?? "s"),
                salida(p[1], e.crudo["toPort"]?.s ?? "n"))
    }

    /// Los codos de rutas largas pueden suavizarse sin perder sus waypoints.
    /// La misma polilínea fina alimenta pintura, agarre y posición de etiqueta.
    static func redondeada(_ e: Elemento) -> [CGPoint]? {
        let radio=e.crudo["cornerRadius"]?.num ?? 0
        let p=e.ruta
        guard radio > 0, p.count > 2 else { return nil }
        var r=[p[0]]
        for i in 1..<(p.count-1) {
            let a=p[i-1],b=p[i],c=p[i+1]
            let l1=hypot(b.x-a.x,b.y-a.y), l2=hypot(c.x-b.x,c.y-b.y)
            guard l1 > 0.001, l2 > 0.001 else { continue }
            let d=min(radio,l1/2,l2/2)
            let u=CGPoint(x:b.x+(a.x-b.x)*d/l1,y:b.y+(a.y-b.y)*d/l1)
            let v=CGPoint(x:b.x+(c.x-b.x)*d/l2,y:b.y+(c.y-b.y)*d/l2)
            r.append(u)
            for k in 1...16 {
                let t=Double(k)/16,q=1-t
                r.append(CGPoint(x:q*q*u.x+2*q*t*b.x+t*t*v.x,y:q*q*u.y+2*q*t*b.y+t*t*v.y))
            }
        }
        r.append(p.last!)
        return r
    }

    static func punto(_ e: Elemento, t: Double) -> CGPoint {
        let p = redondeada(e) ?? e.ruta
        guard p.count >= 2 else { return p.first ?? .zero }
        let t = min(1, max(0, t)), u = 1-t
        if let (a,b) = controles(e) {
            return CGPoint(x:u*u*u*p[0].x+3*u*u*t*a.x+3*u*t*t*b.x+t*t*t*p[1].x,
                           y:u*u*u*p[0].y+3*u*u*t*a.y+3*u*t*t*b.y+t*t*t*p[1].y)
        }
        if e.ruteo == "curva", p.count == 2 {
            let c = CGPoint(x:(p[0].x+p[1].x)/2, y:p[0].y)
            return CGPoint(x:u*u*p[0].x+2*u*t*c.x+t*t*p[1].x,
                           y:u*u*p[0].y+2*u*t*c.y+t*t*p[1].y)
        }
        let largos = zip(p,p.dropFirst()).map { hypot($1.x-$0.x,$1.y-$0.y) }
        var restante = t * largos.reduce(0,+)
        for i in largos.indices {
            if restante <= largos[i], largos[i] > 0 {
                let f = restante/largos[i]
                return CGPoint(x:p[i].x+(p[i+1].x-p[i].x)*f,y:p[i].y+(p[i+1].y-p[i].y)*f)
            }
            restante -= largos[i]
        }
        return p.last!
    }

    static func muestras(_ e: Elemento) -> [CGPoint] {
        if let p=redondeada(e) { return p }
        guard e.ruteo == "curva", e.ruta.count == 2 else { return e.ruta }
        return (0...64).map { punto(e,t:Double($0)/64) }
    }

    static func camino(_ e: Elemento) -> CGPath {
        let path=CGMutablePath(), p=redondeada(e) ?? e.ruta
        guard let inicio=p.first else { return path }
        path.move(to:inicio)
        if let (a,b)=controles(e) { path.addCurve(to:p[1],control1:a,control2:b) }
        else if e.ruteo == "curva", p.count == 2 {
            path.addQuadCurve(to:p[1],control:CGPoint(x:(p[0].x+p[1].x)/2,y:p[0].y))
        } else { for q in p.dropFirst() { path.addLine(to:q) } }
        return path
    }

    /// Busca aire cerca del centro del recorrido; jamás coloca el rótulo en
    /// la punta, donde la siguiente imagen lo tapaba. `labelPosition` permite
    /// una fracción preferida, conservando el rótulo ligado al conector.
    static func cajaEtiqueta(_ e: Elemento, tamano: CGSize, obstaculos: [CGRect]) -> CGRect {
        let preferida=min(0.85,max(0.15,e.crudo["labelPosition"]?.num ?? 0.5))
        var mejor: (CGRect,Double)?
        for t in [preferida,0.35,0.65,0.22,0.78] {
            let p=punto(e,t:t)
            for dy in [-(tamano.height/2+10),tamano.height/2+10,0] {
                let r=CGRect(x:p.x-tamano.width/2,y:p.y+dy-tamano.height/2,width:tamano.width,height:tamano.height)
                let area=obstaculos.reduce(0.0) { sum,o in
                    let i=r.intersection(o.insetBy(dx:-4,dy:-4))
                    return sum+(i.isNull ? 0 : i.width*i.height)
                }
                let score=area*100+abs(t-preferida)*20+abs(dy)*0.01
                if mejor == nil || score < mejor!.1 { mejor=(r,score) }
            }
        }
        return mejor!.0
    }
}
