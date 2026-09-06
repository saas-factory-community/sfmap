#!/usr/bin/env python3
"""
Genera la paleta de Tema.swift LEYENDO `theme/tokens.ts` del lienzo web.

⚠️ POR QUE EXISTE. La primera version de Tema.swift decia "espejo de
tokens.ts" y no lo era: se escribio de memoria con el original a un Read de
distancia. Divergian el fondo del lienzo (#fbfbfd contra #ffffff), la reticula,
los tres colores de texto, y el rol `callout` entero — que en el web es morado y
aqui salio ambar.

No falla nada: los dos lienzos pintan el MISMO documento con colores distintos, y
la unica forma de verlo es poner las dos ventanas lado a lado. Un espejo que hay
que comparar a ojo no es un espejo.

Ahora se DERIVA. Correr `python3 scripts/tema-desde-tokens.py` y volver a
compilar; si el web cambia un tono, aqui cambia con un comando y no con memoria.
"""
import re, sys, pathlib

TOKENS = pathlib.Path.home() / "Developer/business-os/arbrain/src/features/canvas/theme/tokens.ts"
TEMA = pathlib.Path(__file__).parent.parent / "Sources/SFMap/Tema.swift"

src = TOKENS.read_text()

def bloque(nombre):
    """El cuerpo de `export const CLARO: Theme = { ... }`."""
    i = src.index(f"export const {nombre}: Theme = {{")
    j = src.index("\n}\n", i)
    return src[i:j]

def campo(texto, clave):
    m = re.search(rf"\b{re.escape(clave)}:\s*'([^']+)'", texto)
    if not m: raise SystemExit(f"no encontre '{clave}'")
    return m.group(1)

def tintes(texto):
    m = re.search(r"tints:\s*\{(.*?)\n  \},", texto, re.S)
    out = {}
    for n, f, s, l in re.findall(r"(\w+):\s*\{\s*fill:\s*'([^']+)',\s*stroke:\s*'([^']+)',\s*label:\s*'([^']+)'", m.group(1)):
        out[n] = (f, s, l)
    return out

def aristas(texto):
    m = re.search(r"\n  edges:\s*\{(.*?)\n  \},", texto, re.S)
    out = {}
    for n, c, w, e in re.findall(r"(\w+):\s*\{\s*color:\s*'([^']+)',\s*width:\s*([\d.]+),\s*style:\s*'(\w+)'", m.group(1)):
        out[n] = (c, w, e)
    return out

# La forma de cada rol vive en `buildRoles`, una sola vez, y los tonos entran por
# parametro: se leen los dos por separado y se combinan aqui igual que alla.
#
# ⚠️ ESTA TABLA ES EL ESPEJO DE LAS FORMAS y hay que actualizarla CON tokens.ts
# (los tonos sí se leen en vivo; las formas no — la ironía de que este script,
# nacido contra el "se escribió de memoria", la cometió un nivel más adentro el
# 24 ago 2026: el estándar nuevo cambió buildRoles y esta tabla quedó vieja.
# La cazó TemaEspejoTests, que para eso existe).
#
# Estándar firmado 24 ago 2026: módulo ES proceso (el dashed de cajas murió) ·
# la píldora murió (trigger ES proceso) · agente = morado SÓLIDO + fondo pastel
# (el punteado se mudó a las aristas, y allá es dashed) · entregable = ámbar
# pastel + borde mostaza + esquinas de campo + sombra.
FORMA = [
    ("card",        "surface",     "line",            "1.5", "solid", "12", False),
    ("module",      "surface",     "line",            "1.5", "solid", "12", False),
    ("form",        "formFill",    "accent",          "2",   "solid", "4",  False),
    ("callout",     "calloutFill", "accent",          "3.5", "solid", "12", False),
    ("deliverable", "deliverable", "deliverableLine", "1.5", "solid", "4",  True),
    ("trigger",     "surface",     "line",            "1.5", "solid", "12", False),
    ("risk",        "riskFill",    "risk",            "2.5", "solid", "12", False),
    ("agent",       "formFill",    "agentLine",       "2.5", "solid", "12", False),
    ("tray",        "trayFill",    "lineSoft",        "1",   "solid", "20", False),
    ("sticky",      "surfaceAlt",  "lineSoft",        "1",   "solid", "6",  False),
    ("nota",        "notaFill",    "notaLine",        "1",   "solid", "6",  False),
    ("sensor",      "sensorFill",  "sensorLine",      "1.5", "solid", "6",  False),
    ("drawn",       None,          "drawn",           "2.5", "solid", "12", False),
]

def tonos(texto):
    m = re.search(r"roles:\s*buildRoles\(\{(.*?)\}\),", texto, re.S)
    return dict(re.findall(r"(\w+):\s*'([^']+)'", m.group(1)))

def swift(nombre, clave):
    t = bloque(clave)
    tn = tonos(t)
    ar = aristas(t)
    ti = tintes(t)
    L = []
    L.append(f"    static let {nombre}: Tema = Tema(")
    L.append(f'        nombre: "{nombre}",')
    L.append(f'        lienzo: c("{campo(t, "canvas")}"), reticula: c("{campo(t, "grid")}"),')
    L.append(f'        acento: c("{campo(t, "accent")}"), seleccion: c("{campo(t, "accent")}"),')
    txt = re.search(r"\n  text:\s*\{(.*?)\n  \},", t, re.S).group(1)
    def tx(k):
        m = re.search(rf"'?{k}'?:\s*'([^']+)'", txt)
        return m.group(1)
    L.append(f'        tituloTexto: c("{tx("title")}"), cuerpoTexto: c("{tx("body")}"),')
    L.append(f'        pieTexto: c("{tx("caption")}"), chipTexto: c("{tx("chip")}"),')
    L.append(f'        tinta: c("{campo(t, "lapiz")}"),')
    L.append("        roles: [")
    for rol, relleno, trazo, ancho, estilo, radio, sombra in FORMA:
        fill = 'NSColor.clear' if relleno is None else f'c("{tn[relleno]}")'
        L.append(f'            "{rol}": EstiloRol(relleno: {fill}, '
                 f'trazo: Trazo(color: c("{tn[trazo]}"), grosor: {ancho}, estilo: "{estilo}"), '
                 f'radio: {radio}, sombra: {"true" if sombra else "false"}),')
    L.append("        ],")
    L.append("        aristas: [")
    for k, (col, w, e) in ar.items():
        L.append(f'            "{k}": Trazo(color: c("{col}"), grosor: {w}, estilo: "{e}"),')
    L.append("        ],")
    L.append("        tintes: [")
    for k, (f, s, lab) in ti.items():
        L.append(f'            "{k}": (c("{f}"), c("{s}"), c("{lab}")),')
    L.append("        ])")
    return "\n".join(L)

nuevo = swift("claro", "CLARO") + "\n\n" + swift("oscuro", "OSCURO")

tema = TEMA.read_text()
ini = tema.index("    static let claro: Tema")
fin = tema.index("    func rol(_ n: String)")
TEMA.write_text(tema[:ini] + nuevo + "\n\n" + tema[fin:])
print(f"Tema.swift regenerado desde {TOKENS.name}")
