<img src="assets/sfmap.iconset/icon_128x128.png" width="96" align="right" alt="sfmap">

# sfmap

**El lienzo de sistemas, nativo.** App de escritorio macOS para diseñar los
sistemas del negocio: los mapas que antes vivían dentro de Arbrain, ahora en su
propia herramienta.

No reemplaza a Arbrain. Arbrain es el centro de mando; sfmap es la herramienta
de oficio.

---

## Instalar

Tres pasos: compilar, crear las dos tablas, apuntar la app a tu Supabase.

**1. Compilar.** Necesitas macOS 15+ y Xcode (o Command Line Tools) con Swift 6.

```bash
git clone https://github.com/saas-factory-community/sfmap.git
cd sfmap
./scripts/package.sh          # compila, genera el icono, firma e instala
open ~/Applications/sfmap.app
```

**2. Tu backend.** sfmap no trae servidor: guarda tus lienzos en **tu propio**
proyecto de Supabase (el plan gratis alcanza de sobra). Pega
[`supabase/esquema.sql`](supabase/esquema.sql) en el SQL Editor y quedan las dos
tablas que la app usa, `draw` y `draw_folders`.

**3. La credencial.** Crea `~/.sfmap/env` con la URL y la anon key de tu proyecto:

```
MC_SUPABASE_URL=https://TU-PROYECTO.supabase.co
MC_SUPABASE_KEY=TU_ANON_KEY
```

**La credencial nunca se hornea en el bundle**: una llave dentro de un `.app`
viaja con el `.app`. Si algo falla, la app lo dice en `stderr` con el prefijo
`[sfmap]` — abre la Consola y filtra por ahí; el silencio no es una opción.

### Qué es esto y qué no

Es la herramienta con la que Daniel dibuja los sistemas de su negocio, entregada
**tal cual la usa**, no un producto empaquetado. Dos cosas que conviene saber
antes de abrirla:

- **La pared del día es una PLANTILLA.** `Sources/SFMap/Dia/NucleoMonkMode.swift`
  y `NucleoHabitos.swift` traen un reto, una rutina y unos hábitos de ejemplo.
  Son datos, no programa: cámbialos por los tuyos y la pared se pinta sola. Están
  marcados con `── TUYO:` para que los encuentres.
- **Crear diagramas nuevos necesita el compilador**, que es un servicio Node
  aparte (`POST localhost:3000/api/canvas/region`). Sin él sfmap abre, lee,
  mueve, borra y guarda lo que ya existe; lo que no puede es componer un
  diagrama desde cero. Se explica abajo, en "Cómo está hecho".

## Usar

| Gesto | Qué hace |
|---|---|
| arrastrar en vacío | seleccionar |
| ⌥ + arrastrar · botón central | panear |
| arrastrar un elemento | moverlo (se guarda solo, 0.6 s después de soltar) |
| ⇧ + clic | añadir o quitar de la selección |
| pellizco · ⌘ + rueda | zoom |
| `0` | tamaño real |
| `⇧1` | encuadrar (la selección, o todo) |
| `⌘R` | recompilar y recargar la página |

Abrir una página concreta: `open -a sfmap --args <pageId>`.

## Lo que hace hoy

Abre y lista tus lienzos y carpetas · pinta figuras, texto, tinta, secciones y
conectores con los roles y el tema del sistema · sigue el claro/oscuro de macOS
· pan, zoom, encuadrar · seleccionar y arrastrar · **goma de área con alcance
(solo tinta / todo), que marca mientras barre y borra al soltar** · guarda sin
destruir · recuerda dónde lo dejaste.

## Lo que NO hace todavía

Crear elementos · editar texto · deshacer · llamar al compilador desde la app.
Los diagramas se siguen generando por `POST localhost:3000/api/canvas/region`
(ver la skill `canvas` del repo business-os).

---

## Cómo está hecho

```
SUPERFICIE (Swift, este repo)      COMPILADOR (Node, en arbrain/)
pintar · pan · zoom · arrastre     medir texto · componer · dagre · rutear
120 veces por segundo              una vez por diagrama, 110 ms
```

Reescribir el compilador en Swift serían meses —dagre y la medición de fuentes
con fontkit— para ganar en el único eje que no aprieta. La superficie sí gana:
un `NSEvent` toca la cámara y el frame siguiente ya salió, sin bucle de eventos
de navegador, sin React y sin recolector de basura en medio.

**No usa Metal, y es a propósito.** Un lienzo de cientos de elementos con texto
real no está limitado por relleno de píxeles sino por composición de texto, que
CoreText resuelve en CPU de todas formas. Metal añadiría un atlas de glifos y
su invalidación para ganar donde no duele. Si algún día el cuello se **mide** en
rasterizado, se cambia.

| Archivo | Qué es |
|---|---|
| `Json.swift` | valor JSON que conserva lo que no entiende |
| `Modelo.swift` | el elemento: JSON crudo con accesos tipados |
| `Tema.swift` | rol → pintura, claro y oscuro |
| `Fuentes.swift` | los `.ttf` variables, los mismos que mide el compilador |
| `Pintor.swift` | documento → píxeles, CoreGraphics + CoreText |
| `Lienzo.swift` | la vista: eventos, cámara, selección, arrastre |
| `Nube.swift` | leer y escribir la tabla `draw` |
| `main.swift` | ventana, barra, menú |

## El icono

`assets/logo.svg` es la fuente. El icono **es lo que la app hace**: tres nodos
unidos por codos ortogonales, que es la gramática que dibuja el compilador.
Morado en los nodos, oro en las aristas — la materia y la relación, la misma
repartición que usa el lienzo.

`scripts/package.sh` lo regenera cuando el SVG es más nuevo que el `.icns`:
rasteriza con WebKit (siempre está en macOS, no hace falta instalar nada),
**verifica que cada PNG mida lo que su nombre dice**, arma el `.icns` y refresca
la caché de LaunchServices.

---

## Invariantes (romperlos cuesta caro)

1. **Es el MISMO documento que el lienzo web.** Los elementos guardan su JSON
   crudo (`Elemento.crudo`) y al guardar se re-emite entero, así que un campo
   que sfmap aún no conoce SOBREVIVE. Decodificar a una struct cerrada y
   re-serializar lo borraría en silencio — así vació el v3 su capa `regions`.
2. **Guardar re-lee `regions`** antes de escribir y compara `agent_version`.
   Cero filas afectadas es ERROR, jamás un "guardado" silencioso.
3. **Las fuentes son los MISMOS `.ttf`** que mide el compilador. Una fuente
   parecida daría un ancho distinto del que la caja declara, y el texto se
   saldría o quedaría corto sin que nada falle.
4. **Firma con identidad estable (`SFlow Dev`), nunca ad-hoc.** La ad-hoc ancla
   los permisos del sistema al hash del binario: cada rebuild los revoca en
   silencio, con Ajustes mostrándolos concedidos igual.
5. **Nunca pedir `page_elements` para LISTAR.** Medido: 31.92 MB / 8.0 s contra
   0.02 MB / 0.56 s. Factor 1,600 en lo primero que hace la app.
6. **El candado manda.** Un elemento bloqueado no se mueve al arrastrar.

## Bitácora de fallos (lo que costó descubrirlos)

Todos aparecieron **midiendo**, ninguno razonando. Están aquí para que no
vuelvan.

| Fallo | Causa | Cómo se veía |
|---|---|---|
| Icono genérico en el Dock | `snapshotWidth` de WebKit está en PUNTOS: en Retina cada PNG salió al doble. `icon_128x128.png` medía 256 | macOS no encontraba ningún tamaño que buscaba y caía al genérico. El rasterizador imprimía `✓ 128px` igual |
| Falta `icon_32x32@2x` | El nombre `@2x` se derivaba dividiendo entre dos: producía `icon_64x64@2x` (inválido) y se saltaba el que sí hacía falta | Una regla que casi acierta es peor que una tabla de diez líneas |
| Icono recortado | El SVG declara 1024 y WebKit respeta su tamaño natural: en un viewport de 256 solo cabía la esquina | Se arregló envolviéndolo en un HTML que lo escala |
| 8 segundos para abrir | La lista pedía `page_elements` de las 129 páginas solo para poner un número al lado de cada nombre | 31.92 MB por un contador |
| El desplegable decía otra página | `NSPopUpButton.addItem(withTitle:)` ELIMINA cualquier item con ese título antes de añadir: dos lienzos que se muestran igual corren todos los índices | Ahora cada item lleva su `representedObject` |
| La carga fallaba en silencio | Ni error en pantalla ni línea en consola | Por eso existe `traza()` |
| `codesign` rechazaba el bundle | El bundle de recursos de SwiftPM en `Contents/MacOS/` invalida la firma. Y `Bundle.module` hace `fatalError` si falta | Un solo camino de carga: `Contents/Resources/fuentes` |
