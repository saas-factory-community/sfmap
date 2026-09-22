# sfmap · edición pública de SaaS Factory

App nativa AppKit/CoreGraphics, macOS 15+, Swift 6 en modo Swift 5. Lee `README.md`, `docs/portabilidad.md` y `docs/integraciones.md` antes de cambiar distribución o persistencia.

## Contratos

1. **Local por defecto.** Sin configuración usa Application Support/sfmap/Biblioteca. `--local-dir` aísla pruebas y puente. Una caída de nube nunca abre silenciosamente otra biblioteca.
2. **Configuración explícita.** Solo `~/.sfmap/env`; nada de descubrir repos privados o usuarios fijos. URL, clave y UUID de propietario para nube. Nunca empaquetar credenciales.
3. **JSON crudo.** Preservar campos desconocidos, regiones y propiedades de elementos. Para nube, releer antes de guardar y comparar `agent_version` mediante CAS. Cero filas escritas es error.
4. **Portabilidad.** `.sfmap` lleva imágenes embebidas. Se omiten enlaces locales y metadatos privados. HTML/widgets no soportados deben fallar explícitamente. Importar siempre crea una página nueva.
5. **Mismo trazo.** Borrador, commit y recarga pasan por el mismo motor de tinta. No sustituir geometría definitiva con una aproximación distinta en vivo.
6. **Fuentes incluidas.** Resources/fuentes viaja dentro de la app. El build no puede depender del checkout del autor.
7. **Firma estable.** `SFMAP_IDENTITY` selecciona el certificado; jamás fallback ad hoc. `scripts/package.sh --no-install` no reemplaza la app instalada. Versiones anteriores se conservan en dist/previous.
8. **Diseño y foco.** El lienzo es protagonista: barra compacta, estado por color, documentos desactivados por defecto, detalles al acercarse. Mantener tema claro y oscuro legibles.
9. **Edición pública.** Los núcleos de Dia son archivos incluidos con datos demo, no symlinks a sfcal. No importar memorias, métricas, compromisos, IDs ni rutas personales del desarrollo privado.
10. **Verificación.** `swift test`, build release y prueba real importación→exportación de la plantilla. Pruebas de servicios externos son opcionales, explícitas y no acceden a producción.

## Distribución

El repositorio público es `saas-factory-community/sfmap`. La app y la plantilla deben poder abrirse desde un Mac sin infraestructura del autor. No anunciar notarización, soporte Intel o sincronización si no se verificaron.
