-- ESQUEMA MÍNIMO PARA sfmap
-- ---------------------------------------------------------------------------
-- sfmap no trae backend: guarda tus lienzos en TU propio Supabase. Pega esto en
-- el SQL Editor de tu proyecto y listo. Después pon la URL y la anon key en
-- ~/.sfmap/env (ver el README).
--
-- Son dos tablas: una para las páginas (los lienzos) y otra para las carpetas.

create table if not exists draw_folders (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  -- carpetas anidadas: una carpeta puede vivir dentro de otra
  parent_id   uuid references draw_folders(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists draw (
  page_id        uuid primary key default gen_random_uuid(),
  name           text not null,
  folder_id      uuid references draw_folders(id) on delete set null,

  -- EL DOCUMENTO. Un arreglo de elementos en JSON crudo. sfmap lo re-emite
  -- entero al guardar, así que un campo que la app todavía no conoce SOBREVIVE.
  page_elements  jsonb not null default '[]'::jsonb,

  -- Capa aparte que escribe el compilador de diagramas. sfmap la RE-LEE antes de
  -- guardar y nunca la pisa: si la decodificas a una struct cerrada, la borras.
  regions        jsonb,

  -- Contador optimista. Guardar compara este número; si no coincide, alguien
  -- más escribió mientras tanto y el guardado se rechaza en vez de aplastar.
  agent_version  bigint not null default 0,

  -- Dónde dejaste la cámara: {"x":…, "y":…, "zoom":…}
  settings       jsonb,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists draw_folder_id_idx on draw (folder_id);
create index if not exists draw_folders_parent_id_idx on draw_folders (parent_id);

-- ---------------------------------------------------------------------------
-- ACCESO
--
-- sfmap entra con la ANON KEY. Si dejas RLS apagado, cualquiera con esa llave
-- lee y escribe tus lienzos: úsalo solo en un proyecto tuyo y personal.
-- Para algo serio, prende RLS y escribe políticas contra auth.uid():
--
--   alter table draw enable row level security;
--   alter table draw_folders enable row level security;
--   -- y agrega una columna owner uuid references auth.users(id), con políticas
--   -- "owner = auth.uid()" en select/insert/update/delete.
--
-- No lo dejamos hecho a propósito: el modelo de usuarios es TUYO y depende de
-- si esto va a ser una app de una sola persona o de un equipo.
