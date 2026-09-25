# Instala sfmap y abre tu Mapa de Claridad

Guía para cualquier persona, sin conocimientos técnicos. Tiempo: unos 5 minutos.

**Necesitas:** una Mac con chip Apple (M1, M2, M3, M4 o posterior) y macOS 15 Sequoia o más reciente.
No necesitas cuenta, contraseña de nadie, Supabase ni claves de API. Tu mapa vive en tu Mac.

> ¿No sabes qué Mac tienes? Menú  → **Acerca de esta Mac**. Si dice «Chip Apple M…» y «macOS 15» o superior, adelante.
> Si dice «Intel», esta versión todavía no funciona en tu equipo.

## 1. Descarga

1. Abre la [versión 0.3.0](https://github.com/saas-factory-community/sfmap/releases/tag/v0.3.0).
2. En **Assets**, haz clic en `sfmap-0.3.0-macOS-arm64.zip`. Se guarda en tu carpeta **Descargas**.
3. Abre **Descargas** y haz doble clic en el zip. Aparece la carpeta `sfmap-0.3.0` con:
   - `sfmap.app`, la aplicación;
   - `Plantillas/Mapa-de-Claridad.sfmap`, tu mapa del programa;
   - `Plantillas/Tu-negocio.sfmap`, una plantilla adicional;
   - esta guía.

## 2. Instala

Arrastra `sfmap.app` a la carpeta **Aplicaciones** (en la barra lateral de Finder).

## 3. Ábrela la primera vez (el aviso de macOS)

sfmap está firmada, pero todavía **no está notarizada por Apple**. Por eso la primera vez macOS la frena.
Es normal y se resuelve una sola vez:

1. Abre **Aplicaciones** y haz doble clic en **sfmap**. Aparece un aviso que dice que no se pudo verificar.
   Pulsa **Aceptar** (o **Listo**). No la muevas a la papelera.
2. Abre **Ajustes del Sistema** → **Privacidad y seguridad**.
3. Baja hasta la sección **Seguridad**. Verás «Se bloqueó el uso de "sfmap"…». Pulsa **Abrir de todos modos**.
4. Escribe la contraseña de tu Mac (o usa Touch ID) y confirma **Abrir de todos modos** otra vez.

Listo: desde ahora sfmap abre normal, con doble clic o desde Spotlight (⌘ espacio → «sfmap»).

**No desactives Gatekeeper ni la seguridad de tu Mac.** Solo autorizas esta aplicación concreta.

### Si macOS dice «sfmap está dañado y no se puede abrir»

A veces pasa con apps descargadas que aún no están notarizadas. Solo si descargaste el zip desde el enlace
oficial de arriba, abre la app **Terminal** (⌘ espacio → «Terminal»), pega esta línea y pulsa Intro:

```bash
xattr -dr com.apple.quarantine /Applications/sfmap.app
```

Quita la marca de «descargado de internet» únicamente de sfmap. Después vuelve a abrirla con doble clic.

## 4. Tu Mapa de Claridad ya está abierto

La primera vez que abres sfmap, tu **Mapa de Claridad · Arbrain** aparece solo, encuadrado y listo para
llenar. Es tuyo y vive en tu Mac.

¿Lo borraste o quieres una copia limpia? Engrane (abajo) → **Importar .sfmap…** →
`Descargas/sfmap-0.3.0/Plantillas/Mapa-de-Claridad.sfmap`. También sirve doble clic en el archivo desde Finder.
Importar siempre crea una copia nueva; no toca la que ya llenaste.

## 5. Úsalo

| Quiero… | Hago… |
| --- | --- |
| Ver todo el mapa | ⇧1 |
| Acercarme o alejarme | ⌘ + rueda del ratón, o pellizco en el trackpad |
| Moverme | Rueda / dos dedos |
| Cambiar un texto | Doble clic sobre él |
| Deshacer | ⌘Z |
| Ver todos los atajos | ⌘/ |

**Cómo se llena:** lo escrito en **violeta** es el ejemplo ficticio de Ana (clínicas dentales).
Haz doble clic y reemplázalo por lo tuyo. Lo que dice «Escribe aquí…» espera tu respuesta.
Borde **punteado** = por construir; **sólido** = ya existe. Cambia el borde cuando lances algo.

Se guarda solo, en tu Mac: `~/Library/Application Support/sfmap/Biblioteca`.

## 6. Comparte o respalda

- **Enviar tu mapa** a tu consultor: engrane → **Descargar lienzo…**. Las imágenes viajan dentro del archivo.
- **Respaldo:** cierra sfmap y copia juntas las carpetas `Biblioteca` e `Imagenes` de
  `~/Library/Application Support/sfmap/`.
- Importar dos veces crea dos copias; no se sobrescribe nada.

## Si algo falla

- **No veo el mapa:** pulsa ⇧1.
- **Error al importar:** usa un `.sfmap` descargado de la release; no cambies extensiones de archivos.
- **La app no abre tras el paso 3:** revisa que tu Mac sea Apple Silicon con macOS 15 o superior.
- **Configuraste una nube y falla:** la app muestra el error; no cambia sola a otra biblioteca.
  Para abrir la biblioteca local: `/Applications/sfmap.app/Contents/MacOS/sfmap --local` en Terminal.
- **Otra cosa:** escribe en el canal del programa con una captura del mensaje. Nunca compartas contraseñas.

¿Prefieres compilarla tú? Consulta «Compilar desde el código» en el [README](../README.md).
