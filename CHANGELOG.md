# Cambios

## 0.3.0 · 25 septiembre 2026

- Plantilla **Mapa de Claridad · Arbrain**: el entregable de F0 (tu mapa) y F1 (tu oferta en una página)
  del programa. Siete piezas con ejemplo ficticio editable, hoja de oferta que se arma con las piezas y
  recorrido de 90 días a escala. Ilustraciones propias embebidas; legible en tema claro y oscuro.
- Primer arranque: una biblioteca local nueva abre el Mapa de Claridad ya encuadrado, sin importar nada.
  Si la persona lo borra, no reaparece.
- Guía de instalación reescrita para personas no técnicas, con el paso «Abrir de todos modos» de macOS 15.
- Guion de video tutorial (`docs/guion-video.md`) y pasos de notarización pendientes (`docs/notarizacion.md`).
- `scripts/release.sh`: zip de app + plantillas + guía, plantillas sueltas y `SHA256SUMS`.
- Prueba de que la plantilla incluida abre sin recursos externos y hace ida y vuelta sin alterar el documento.
- Sin cambios de código del editor: las correcciones del desarrollo privado ya estaban en 0.2.0.


## 0.2.0 · 22 septiembre 2026 · evaluación

- Biblioteca local sin cuenta ni backend, con páginas, carpetas y guardado por versión.
- Importación y exportación `.sfmap`: plantillas editables con imágenes incluidas.
- Plantilla **Tu negocio, de punta a punta** con 200 elementos nativos.
- Engrane de ajustes: archivos, minimapa, apertura de documentos, tema y fondo.
- Barra de estado compacta: indicador por color y control de documentos; los controles de tema, zoom y PNG siguen accesibles desde atajos/menús.
- Mejoras de selección, edición de texto, colores, conectores, recorte, zoom y documentos HTML.
- Navegación a elementos y detalles de sistemas; mejoras de legibilidad al alejar el lienzo.
- Conservación de campos desconocidos al guardar y detección de conflictos de versión.
- Compatibilidad con Swift 6.1 y radios de dibujo seguros en macOS 15, incluso en controles con recorrido cero.
- Distribución pública independiente de rutas, archivos y cuentas del autor.
- Instrucciones de instalación/importación y empaquetado sin instalar sobre la aplicación del desarrollador.

Limitaciones: binario distribuido para Apple Silicon/macOS 15+, firma local sin notarización Apple; biblioteca local sin sincronización automática; HTML y widgets vivos no exportables a `.sfmap` todavía.
