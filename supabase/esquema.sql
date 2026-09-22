-- OPCIONAL: backend personal dedicado. La app funciona localmente sin esto.
-- Revisar antes de ejecutar. No se aplica automáticamente.
-- Usa service_role solo en tu equipo; no distribuyas esa clave ni desactives RLS.

create table if not exists public.draw_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  name text not null,
  parent_id uuid references public.draw_folders(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.draw (
  page_id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  name text not null,
  folder_id uuid references public.draw_folders(id) on delete set null,
  page_elements jsonb not null default '{"schemaVersion":4,"elements":[]}'::jsonb,
  agent_version bigint not null default 0,
  is_deleted boolean not null default false,
  settings jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Compatibilidad aditiva con el esquema de 0.1. No asignar dueño a datos ajenos.
alter table public.draw add column if not exists user_id uuid;
alter table public.draw add column if not exists is_deleted boolean not null default false;
alter table public.draw_folders add column if not exists user_id uuid;
alter table public.draw alter column page_elements set default '{"schemaVersion":4,"elements":[]}'::jsonb;
-- Si las tablas ya existían, asigna tus filas antiguas a TU UUID antes de usar
-- MC_USER_ID. Los NULL quedan fuera de la lista; el script no modifica su dueño.

create index if not exists draw_owner_idx on public.draw (user_id, is_deleted);
create index if not exists draw_folder_id_idx on public.draw (folder_id);
create index if not exists draw_folders_owner_idx on public.draw_folders (user_id);
create index if not exists draw_folders_parent_id_idx on public.draw_folders (parent_id);

alter table public.draw enable row level security;
alter table public.draw_folders enable row level security;
-- No se crean políticas para anon/authenticated. La app de esta versión usa
-- una credencial administrativa de un backend personal, no sesiones de usuarios.
-- Si ya existen políticas en tu proyecto, revísalas: este script no las borra.
