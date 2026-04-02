-- ═══════════════════════════════════════════════════════════════════
--  SABOR — Schema Supabase
--  Corre este SQL en el SQL Editor de tu proyecto Supabase
--  https://supabase.com/dashboard → SQL Editor → New query
-- ═══════════════════════════════════════════════════════════════════


-- ── 1. PROFILES ─────────────────────────────────────────────────────
create table if not exists profiles (
  id          uuid references auth.users on delete cascade primary key,
  username    text unique,
  name        text,
  bio         text,
  avatar_url  text,
  created_at  timestamp with time zone default timezone('utc', now())
);

alter table profiles enable row level security;

create policy "Cualquiera puede ver perfiles"
  on profiles for select using (true);

create policy "El usuario puede actualizar su propio perfil"
  on profiles for update using (auth.uid() = id);

create policy "El usuario puede insertar su propio perfil"
  on profiles for insert with check (auth.uid() = id);


-- ── 2. FUNCIÓN + TRIGGER (auto-crear perfil vacío al registrarse) ───
--  Nota: esta función crea un perfil vacío; la app llena name/username
--  después del sign-up.  Si ya tienes esta función, puedes saltarla.

create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();


-- ── 3. RESTAURANTS ──────────────────────────────────────────────────
create table if not exists restaurants (
  id            uuid default gen_random_uuid() primary key,
  user_id       uuid references profiles(id) on delete cascade not null,
  name          text not null,
  neighborhood  text,
  cuisine       text,
  rating        integer check (rating between 1 and 5),
  notes         text,
  emoji         text,
  cover_photo   text,          -- data-URL o URL externa
  lat           float,
  lng           float,
  place_id      text,
  is_public     boolean default true,
  visited_at    date,          -- fecha de visita (distinta de created_at)
  posts         jsonb default '[]'::jsonb,  -- momentos/fotos del restaurante
  created_at    timestamp with time zone default timezone('utc', now())
);

alter table restaurants enable row level security;

-- Sólo el dueño puede leer sus restaurantes
create policy "El usuario ve sus propios restaurantes"
  on restaurants for select using (auth.uid() = user_id);

-- Sólo el dueño puede insertar
create policy "El usuario inserta sus propios restaurantes"
  on restaurants for insert with check (auth.uid() = user_id);

-- Sólo el dueño puede editar
create policy "El usuario actualiza sus propios restaurantes"
  on restaurants for update using (auth.uid() = user_id);

-- Sólo el dueño puede borrar
create policy "El usuario borra sus propios restaurantes"
  on restaurants for delete using (auth.uid() = user_id);


-- ═══════════════════════════════════════════════════════════════════
--  NOTAS
--  • La columna `posts` guarda los "momentos" como JSONB array.
--    Cada elemento tiene: { id, photo, caption, date }
--  • La columna `cover_photo` admite data-URLs (base64) o URLs externas.
--    Si el proyecto crece, considera mover las fotos a Supabase Storage.
--  • Activa / desactiva la confirmación de email en:
--    Supabase Dashboard → Authentication → Providers → Email
-- ═══════════════════════════════════════════════════════════════════
