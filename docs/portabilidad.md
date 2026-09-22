# Archivos `.sfmap`

Un archivo incluye el nombre, el documento y sus imágenes. Importar crea una página nueva con identificador propio, conservando los identificadores internos de los elementos y sus conexiones.

```json
{
  "format": "sfmap",
  "version": 1,
  "kind": "template",
  "name": "Mi mapa",
  "document": {"schemaVersion": 4, "elements": []}
}
```

`kind` admite `template` o `canvas`; ambos son editables. El formato conserva posiciones, estilos, texto, conexiones y campos desconocidos compatibles. Las imágenes van como `data:image/...;base64`.

Al exportar se omiten enlaces a documentos/archivos locales, enlaces a otras páginas, regiones compiladas y marcas del generador. Los enlaces web y `node:` sobreviven. El texto visible no se anonimiza: revisa lo que compartes.

Los objetos HTML, embeds y widgets vivos todavía no son portátiles. La exportación los rechaza con un error explícito. Límites: 128 MB por documento, 20.000 elementos y 32 MB por imagen decodificada.

## CLI para agentes y pruebas

Ejemplos después de `swift build`, con una biblioteca aislada:

```bash
.build/debug/SFMap --local-dir /tmp/sfmap-demo --portable-import templates/tu-negocio/Tu-negocio.sfmap
# Devuelve IMPORT_OK <id>
.build/debug/SFMap --local-dir /tmp/sfmap-demo --portable-export <id> /tmp/mi-mapa.sfmap --template
```

`--local` fuerza la biblioteca local habitual. `--local-dir <ruta>` crea o utiliza otra biblioteca y separa también el puente de órdenes de agentes. Evita que las pruebas escriban en tu trabajo diario.

La biblioteca guarda JSON con escrituras atómicas y comprobación de versión. La importación desde la interfaz espera el guardado del mapa abierto antes de cambiar de página.
