# Instalar y abrir tu primera plantilla

## Descarga para miembros

1. Abre la [versión 0.2.0](https://github.com/saas-factory-community/sfmap/releases/tag/v0.2.0).
2. Descarga `sfmap-0.2.0-macOS-arm64.zip`. Incluye la aplicación, la plantilla y esta guía.
3. Descomprime y mueve `sfmap.app` a Aplicaciones. Requiere **Mac con Apple Silicon y macOS 15+**. Este binario no sirve para Windows ni para Mac Intel.
4. Abre sfmap, pulsa el engrane y selecciona **Importar .sfmap…**.
5. Elige `Tu-negocio.sfmap`. Aparecerá un lienzo nuevo en tu biblioteca local.

No necesitas Supabase, claves de API, una cuenta ni tener instalado el repositorio.

## Aviso de macOS

Esta es una **distribución de evaluación**, firmada con un certificado local. Aún no está notarizada ni firmada con Developer ID de Apple. Eso puede generar un aviso de desarrollador no verificado.

Si confías en el origen de la descarga y macOS ofrece **Abrir de todos modos** en Ajustes del Sistema → Privacidad y seguridad, puedes autorizar esa aplicación concreta. No desactives Gatekeeper globalmente. Si no deseas autorizarla, utiliza la opción de compilar desde el código descrita en el README.

## Tu trabajo

- Se guarda automáticamente en `~/Library/Application Support/sfmap/Biblioteca`.
- Las imágenes pegadas quedan en `~/Library/Application Support/sfmap/Imagenes`.
- Para hacer respaldo, cierra la app y copia esas dos carpetas juntas.
- Para enviar un mapa: engrane → **Descargar lienzo…**. Las imágenes viajan dentro del archivo.
- Para crear una plantilla: engrane → **Descargar plantilla…**. También es editable.
- Importar siempre crea una página nueva. Importar dos veces produce dos copias.

## Si algo no aparece

**No veo el mapa:** pulsa ⇧1 para encuadrar. **No quiero abrir documentos al pulsar:** deja desactivada esa opción en el engrane. **No encuentro una herramienta:** ⌘/ muestra todos los atajos.

**Error al importar:** utiliza un `.sfmap` exportado con esta versión. No cambies la extensión de un PNG o un JSON cualquiera. El formato no acepta HTML ni widgets conectados y tiene un límite de 128 MB.

**Error de nube después de configurar Supabase:** la app conserva el error; no cambia silenciosamente a una biblioteca vacía. Para abrir la biblioteca local explícitamente, ejecuta desde Terminal:

```bash
/Applications/sfmap.app/Contents/MacOS/sfmap --local
```

Puedes compartir el mensaje de error en un issue, ocultando tus claves y contenido privado.
