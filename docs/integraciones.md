# Integraciones opcionales

**Para dibujar, importar y compartir plantillas no necesitas nada de esta página.** sfmap funciona localmente por defecto.

## Supabase propio

La conexión remota es una integración avanzada para un **proyecto dedicado, personal y administrado por ti**. No incluye registro de usuarios, inicio de sesión ni aislamiento multitenant. No distribuyas un archivo de configuración compartido a tus clientes.

1. Revisa y ejecuta `supabase/esquema.sql` en un proyecto de prueba propio. El script no se ejecuta desde la app.
2. Crea `~/.sfmap/env`, fuera del repositorio, con:

```dotenv
MC_SUPABASE_URL=https://TU-PROYECTO.supabase.co
MC_SUPABASE_KEY=TU_SERVICE_ROLE_KEY
MC_USER_ID=TU_UUID_DE_PROPIETARIO
```

3. Restringe ese archivo al usuario del equipo: `chmod 600 ~/.sfmap/env`.
4. Reinicia sfmap. Sin estas variables se abre la biblioteca local; una configuración de nube incompleta muestra error.

El UUID es obligatorio y debe corresponder al `user_id` de tus filas. Una clave `service_role` tiene privilegios administrativos: úsala solo en tu equipo y backend propios. El esquema mantiene RLS activado sin políticas anónimas. La clave pública/anon por sí sola no sirve con esta configuración.

Si ya tenías tablas, haz una copia antes de aplicar cambios y revisa los `user_id` antiguos: el script **no asigna dueño a filas existentes**. Los datos locales no se migran automáticamente a la nube; puedes exportar/importar `.sfmap`.

## Documentos y HTML

Los enlaces `doc:ruta.md` se resuelven dentro de `~/Library/Application Support/sfmap/Documentos`. Puedes elegir otra raíz con `SFMAP_REPO`. Su apertura al pulsar está desactivada por defecto. El editor también puede presentar HTML; abre únicamente contenido de confianza. HTML y widgets conectados quedan fuera de la exportación portátil.

## Widgets y compilador

El código conserva adaptadores opcionales para sfcal, Google Calendar, Todoist, métricas y un compilador web externo. Esos servicios **no se incluyen** y no son necesarios para la plantilla. En modo local no arranca el lector de esas integraciones.

Los ejemplos de hábitos y metas son datos de demostración que puedes personalizar en el código. No son información de tu negocio. Los tokens opcionales se leen de `~/.sfmap/env` o de la configuración de sfcal en tu propio equipo; nunca vienen incluidos.

Para el compilador externo se usan `SFMAP_CANVAS_URL` y `OPENCLAW_GATEWAY_TOKEN`. Las pruebas comparativas del tema web requieren `SFMAP_TOKENS`; el banco Node de tinta requiere instalar `perfect-freehand` en el checkout. Ninguna de esas dependencias afecta al uso normal de la app.
