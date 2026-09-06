# sfmap — el lienzo de sistemas, nativo

App de escritorio macOS en Swift para el canvas v4 de Arbrain. **No reemplaza a
Arbrain**: Arbrain es el centro de mando; sfmap es la herramienta de oficio para
diseñar los sistemas del negocio.

## El reparto, y por qué

```
SUPERFICIE (Swift, aquí)          COMPILADOR (Node, en arbrain/)
pintar · pan · zoom · arrastre    medir texto · componer · dagre · rutear
120 veces por segundo             una vez por diagrama, 110 ms
```

Reescribir el compilador en Swift serían meses (dagre + medición de fuentes con
fontkit) para ganar en el único eje que no aprieta. La superficie sí gana: un
`NSEvent` toca la cámara y el frame siguiente ya salió, sin bucle de eventos de
navegador, sin React y sin recolector de basura en medio.

## Comandos

```bash
swift build                 # compilar
swift run SFMap             # correr desde el código
./scripts/package.sh        # .app firmado + instalar en ~/Applications
./scripts/package.sh && open ~/Applications/sfmap.app
swiftc -O scripts/icono.swift -o /tmp/i && /tmp/i . && iconutil -c icns assets/sfmap.iconset -o assets/icon.icns

# EL BANCO DE TRAZOS — el motor de tinta no se juzga con adjetivos
node scripts/banco-web.mjs banco/trazos.json /tmp/banco   # contornos del referente web
swift run -c release SFMap --banco /tmp/banco --hoja sfmap,viejo,web-pf,web-v4
swift run -c release SFMap --banco /tmp/banco --ab sfmap,web-pf --semilla 41  # A/B ciego
swift run -c release SFMap --banco /tmp/d --solo real-firma --escala 12       # detalle
swift run -c release SFMap --escena sonda-tinta --sin-guardar                 # latencia real
node scripts/verificar-formato.mjs /tmp/trazo-sfmap.json                      # ida y vuelta
```

Abrir una página concreta: `open -a sfmap --args <pageId>`.

## Invariantes (romperlos cuesta caro)

1. **Es el MISMO documento que el lienzo web.** Los elementos guardan su JSON
   crudo (`Elemento.crudo`) y al guardar se re-emite entero. Un campo que sfmap
   no conoce SOBREVIVE. Decodificar a una struct cerrada y re-serializar
   borraría en silencio lo que aún no comprende — así vació el v3 su capa
   `regions`.
2. **Guardar re-lee `regions` antes de escribir** y compara `agent_version`.
   Cero filas afectadas es ERROR, nunca un "guardado" silencioso.
3. **El motor de tinta es una FUNCIÓN PURA de los puntos** (`Tinta.camino`).
   No tiene modo "en vivo". El referente web sí (`last: !live`) y con él el
   borrador y el trazo guardado son dos dibujos distintos; aquí la divergencia
   no se vigila, no existe. El dibujo en curso y el elemento guardado salen del
   mismo código con los mismos números — medido: los 16 casos del banco dan
   PNG byte-idénticos por los dos caminos.
   Corolario: nada que dependa del reloj de pared o de estado externo puede
   entrar en el motor, o el trazo dejaría de ser reproducible.

4. **Los campos de la pluma son ADITIVOS y CONDICIONALES.** Un punto guarda
   `x`, `y`, `pressure` siempre, y `tiltX`/`tiltY`/`t` **solo si existen**. El
   lienzo web lee los tres primeros, ignora el resto y lo conserva al guardar
   (verificado con `scripts/verificar-formato.mjs`). Escribir `tilt: 0` para un
   ratón sería inventar un dato: "sin inclinación" y "vertical" no son lo mismo,
   y el motor los distingue.

5. **Se cuantiza en la CAPTURA, no al guardar** (`puntoDePluma`): centésimas de
   unidad en x/y, décimas de ms en t. Recortar al guardar dejaría el borrador y
   el guardado con números distintos en el último decimal — y ahí se acabó el
   invariante 3. De paso, el JSON de un trazo de 600 puntos baja de 53 KB a 31.

6. **Las fuentes son los MISMOS `.ttf`** que mide el compilador, copiados a
   `Resources/fuentes` y empaquetados en `Contents/Resources/fuentes`. Una
   fuente parecida daría un ancho distinto del que la caja declara.
7. **Firma con identidad estable ("SFlow Dev"), nunca ad-hoc.** La ad-hoc ancla
   los permisos al hash del binario y cada rebuild los revoca en silencio.
8. **Nunca pedir `page_elements` para LISTAR.** Medido: 31.92 MB / 8.0 s contra
   0.02 MB / 0.56 s. El contador se rellena al abrir.
9. **La credencial se lee de `agent-server/.env`** (o `~/.sfmap/env`) y jamás se
   hornea en el bundle: una llave dentro de un .app viaja con el .app.

## Lo que hace hoy

Abre · lista tus lienzos y carpetas · pinta figuras, texto, **tinta de plumilla**
(spline centrípeta, ancho continuo por presión/velocidad/inclinación, plumilla
elíptica con el tilt de la PW600L — ver `Sources/SFMap/Tinta.swift`), secciones y
conectores con los roles y el tema del sistema · claro/oscuro siguiendo a macOS
· pan, zoom, encuadrar (⇧1), tamaño real (0) · seleccionar y arrastrar ·
guarda sin destruir · recuerda dónde lo dejaste.

## Lo que NO hace todavía

Crear elementos · editar texto · deshacer · llamar al compilador desde la app
(hoy los diagramas se generan por `POST localhost:3000/api/canvas/region`).
