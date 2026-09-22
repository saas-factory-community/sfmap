import AppKit

/// Preferencias de lectura por dispositivo, independientes del documento compartido.
enum PreferenciasLienzo {
    static func minimapa(_ d:UserDefaults = .standard) -> Bool {
        d.object(forKey:"sfmap.minimapa") as? Bool ?? true
    }
    static func fijarMinimapa(_ v:Bool, _ d:UserDefaults = .standard) { d.set(v,forKey:"sfmap.minimapa") }
}

final class Ajustes: NSViewController {
    var alAccion:((String)->Void)?
    var alMinimapa:((Bool)->Void)?
    var alDocumentos:((Bool)->Void)?
    var alTema:((String)->Void)?
    var alFondo:((Fondo)->Void)?
    private let tema:Tema
    private let docs:Bool, mapa:Bool, local:Bool, tienePagina:Bool
    private let nombreTema:String, fondo:Fondo
    init(tema:Tema, docs:Bool, mapa:Bool, local:Bool, tienePagina:Bool, nombreTema:String, fondo:Fondo) {
        self.tema=tema;self.docs=docs;self.mapa=mapa;self.local=local;self.tienePagina=tienePagina;self.nombreTema=nombreTema;self.fondo=fondo
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func loadView() {
        let v=Tarjeta(tema:tema,radio:16);v.frame=NSRect(x:0,y:0,width:360,height:490);view=v
        func label(_ s:String,_ y:CGFloat,_ size:CGFloat=11,_ weight:Int=650) {
            let l=NSTextField(labelWithString:s);l.font=Estilo.fuente(size,CGFloat(weight));l.textColor=tema.tituloTexto
            l.frame=NSRect(x:22,y:y,width:318,height:24);v.addSubview(l)
        }
        label("Ajustes",446,20,750)
        label(local ? "Biblioteca local · en este Mac" : "Biblioteca conectada",421,11,500)
        label("ARCHIVOS",386)
        for (i,p) in [("plantilla","Descargar plantilla…"),("lienzo","Descargar lienzo…"),("importar","Importar .sfmap…")].enumerated() {
            let b=NSButton(title:p.1,target:self,action:#selector(accion(_:)));b.identifier=NSUserInterfaceItemIdentifier(p.0)
            b.bezelStyle = .rounded;b.alignment = .left;b.font=Estilo.fuente(12,600)
            b.frame=NSRect(x:18,y:352-CGFloat(i)*34,width:324,height:30)
            b.isEnabled=tienePagina || p.0 == "importar";v.addSubview(b)
        }
        label("LECTURA",244)
        for (i,p) in [("mapa","Mostrar minimapa",mapa),("docs","Abrir documentos al pulsar",docs)].enumerated() {
            let b=NSButton(checkboxWithTitle:p.1,target:self,action:#selector(toggle(_:)))
            b.identifier=NSUserInterfaceItemIdentifier(p.0);b.state=p.2 ? .on:.off
            b.font=Estilo.fuente(12,550);b.frame=NSRect(x:22,y:216-CGFloat(i)*31,width:316,height:25);v.addSubview(b)
        }
        label("Tema",143,12,550); label("Fondo",104,12,550)
        let tp=NSPopUpButton(frame:NSRect(x:143,y:143,width:192,height:27));tp.addItems(withTitles:["Sistema","Claro","Oscuro"])
        tp.selectItem(at:nombreTema == "claro" ? 1 : nombreTema == "oscuro" ? 2:0);tp.target=self;tp.action=#selector(temaElegido(_:));v.addSubview(tp)
        let fp=NSPopUpButton(frame:NSRect(x:143,y:104,width:192,height:27));fp.addItems(withTitles:Fondo.allCases.map(\.nombre));fp.selectItem(at:Fondo.allCases.firstIndex(of:fondo) ?? 1)
        fp.target=self;fp.action=#selector(fondoElegido(_:));v.addSubview(fp)
        let a=NSButton(title:"Atajos de teclado",target:self,action:#selector(accion(_:)));a.identifier=NSUserInterfaceItemIdentifier("atajos")
        a.bezelStyle = .rounded;a.frame=NSRect(x:18,y:48,width:324,height:30);v.addSubview(a)
        label("⌘ + rueda para acercarte · T cambia el tema",12,10,500)
    }
    @objc private func accion(_ b:NSButton) { alAccion?(b.identifier!.rawValue) }
    @objc private func toggle(_ b:NSButton) { if b.identifier?.rawValue == "mapa" { alMinimapa?(b.state == .on) } else { alDocumentos?(b.state == .on) } }
    @objc private func temaElegido(_ b:NSPopUpButton) { alTema?(["sistema","claro","oscuro"][b.indexOfSelectedItem]) }
    @objc private func fondoElegido(_ b:NSPopUpButton) { alFondo?(Fondo.allCases[b.indexOfSelectedItem]) }
}
