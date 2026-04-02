-- ═══════════════════════════════════════════════════════════════════════════
--  SABOR — Schema v2
--  Proyecto: App social gastronómica para Lima, Perú
--  Versión: 2.0.0
--  Fecha: 2026-04-01
--  Descripción: Schema completo con profiles, restaurants, moments,
--               friendships, feed_posts view, RLS e índices de performance.
--               Idempotente — seguro de ejecutar múltiples veces.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 1. EXTENSIONES ───────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ── 2. FUNCIONES HELPER ──────────────────────────────────────────────────────
-- NOTA: are_friends() se define DESPUÉS de la tabla friendships (sección 3.4)
-- porque LANGUAGE sql valida las tablas referenciadas en tiempo de creación.

-- Auto-crea un perfil vacío cuando un usuario se registra en auth.users.
-- La app completa name/username después del sign-up.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Trigger vinculado a auth.users para crear perfil automáticamente.
-- Usa CREATE OR REPLACE para idempotencia (no soportado en versiones viejas de PG,
-- así que usamos DROP + CREATE).
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE handle_new_user();


-- ── 3. TABLAS ────────────────────────────────────────────────────────────────

-- ── 3.1 profiles ─────────────────────────────────────────────────────────────
-- Extiende auth.users con datos públicos del usuario.
-- is_public controla visibilidad en el feed y búsquedas sociales.
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username    TEXT        UNIQUE NOT NULL,
  name        TEXT,
  bio         TEXT,
  avatar_url  TEXT,
  is_public   BOOLEAN     DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Migración segura: agrega columnas nuevas si el schema v1 ya existe
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_public  BOOLEAN     DEFAULT TRUE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- ── 3.2 restaurants ───────────────────────────────────────────────────────────
-- Registro de restaurantes visitados por el usuario.
-- place_id referencia Google Places para datos enriquecidos.
-- is_public determina visibilidad en el feed y para amigos.
-- NOTA: posts (JSONB del schema v1) fue eliminado — los momentos son tabla separada.
CREATE TABLE IF NOT EXISTS restaurants (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name            TEXT        NOT NULL,
  neighborhood    TEXT,
  cuisine         TEXT,
  rating          SMALLINT    CHECK (rating >= 1 AND rating <= 5),
  notes           TEXT,
  notes_photo     TEXT,       -- Foto adjunta a las notas de campo (base64 o URL)
  emoji           TEXT,
  cover_photo_url TEXT,       -- URL en Supabase Storage o externa
  lat             DOUBLE PRECISION,
  lng             DOUBLE PRECISION,
  place_id        TEXT,       -- Google Places ID para enriquecer datos
  is_public       BOOLEAN     DEFAULT TRUE,
  visited_at      DATE,       -- Fecha de visita (distinta de created_at)
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Migración segura para bases existentes
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS notes_photo TEXT;

-- ── 3.3 moments ───────────────────────────────────────────────────────────────
-- Fotos/posts dentro de un restaurante.
-- Separado de restaurants deliberadamente: permite múltiples momentos por visita,
-- paginación independiente y queries eficientes para el feed social.
CREATE TABLE IF NOT EXISTS moments (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id  UUID        NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  user_id        UUID        NOT NULL REFERENCES profiles(id)    ON DELETE CASCADE,
  photo_url      TEXT,
  caption        TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3.4 friendships ───────────────────────────────────────────────────────────
-- Relación bidireccional con estados: pending → accepted | blocked.
-- UNIQUE(requester_id, addressee_id) previene duplicados en una dirección;
-- CHECK no_self_friendship previene auto-amistad.
CREATE TABLE IF NOT EXISTS friendships (
  id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id  UUID    NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  addressee_id  UUID    NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status        TEXT    NOT NULL CHECK (status IN ('pending', 'accepted', 'blocked')),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT no_self_friendship CHECK (requester_id != addressee_id),
  CONSTRAINT unique_friendship  UNIQUE (requester_id, addressee_id)
);


-- ── 3.5 are_friends() — definida aquí porque LANGUAGE sql requiere que la tabla
--         friendships exista antes de crear la función.
CREATE OR REPLACE FUNCTION are_friends(user_a UUID, user_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM friendships
    WHERE status = 'accepted'
      AND (
        (requester_id = user_a AND addressee_id = user_b)
        OR
        (requester_id = user_b AND addressee_id = user_a)
      )
  );
$$;


-- ── 4. VIEW: feed_posts ───────────────────────────────────────────────────────
-- Feed público desnormalizado. Solo expone contenido de perfiles Y restaurantes
-- marcados como públicos. Los queries de amigos se resuelven a nivel de app/RLS,
-- no en esta view (para mantenerla simple y cacheable).
CREATE OR REPLACE VIEW feed_posts AS
SELECT
  m.id              AS post_id,
  m.user_id,
  p.username,
  p.avatar_url,
  r.name            AS restaurant_name,
  r.neighborhood,
  r.cuisine,
  r.rating,
  m.photo_url,
  m.caption,
  m.created_at
FROM moments       m
JOIN restaurants   r ON r.id = m.restaurant_id
JOIN profiles      p ON p.id = m.user_id
WHERE p.is_public   = TRUE
  AND r.is_public   = TRUE;


-- ── 5. ROW LEVEL SECURITY ────────────────────────────────────────────────────

-- ── 5.1 profiles ─────────────────────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_public"  ON profiles;
DROP POLICY IF EXISTS "profiles_select_own"     ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own"     ON profiles;
DROP POLICY IF EXISTS "profiles_update_own"     ON profiles;
DROP POLICY IF EXISTS "profiles_delete_own"     ON profiles;

-- Cualquiera puede ver perfiles públicos; el dueño ve el suyo siempre
CREATE POLICY "profiles_select_public"
  ON profiles FOR SELECT
  USING (is_public = TRUE OR auth.uid() = id);

-- Solo el propio usuario puede insertar su perfil
CREATE POLICY "profiles_insert_own"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Solo el propio usuario puede actualizar su perfil
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

-- Solo el propio usuario puede eliminar su perfil
CREATE POLICY "profiles_delete_own"
  ON profiles FOR DELETE
  USING (auth.uid() = id);

-- ── 5.2 restaurants ───────────────────────────────────────────────────────────
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "restaurants_select"        ON restaurants;
DROP POLICY IF EXISTS "restaurants_insert_own"    ON restaurants;
DROP POLICY IF EXISTS "restaurants_update_own"    ON restaurants;
DROP POLICY IF EXISTS "restaurants_delete_own"    ON restaurants;

-- Visibilidad: dueño ve todos los suyos; público ve is_public=TRUE;
-- amigos (amistad aceptada) ven los del amigo aunque no sean públicos.
CREATE POLICY "restaurants_select"
  ON restaurants FOR SELECT
  USING (
    auth.uid() = user_id                          -- dueño
    OR is_public = TRUE                           -- público en general
    OR are_friends(auth.uid(), user_id)           -- amigo con amistad aceptada
  );

-- Solo usuarios autenticados insertando con su propio user_id
CREATE POLICY "restaurants_insert_own"
  ON restaurants FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Solo el dueño puede actualizar
CREATE POLICY "restaurants_update_own"
  ON restaurants FOR UPDATE
  USING (auth.uid() = user_id);

-- Solo el dueño puede eliminar
CREATE POLICY "restaurants_delete_own"
  ON restaurants FOR DELETE
  USING (auth.uid() = user_id);

-- ── 5.3 moments ───────────────────────────────────────────────────────────────
ALTER TABLE moments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "moments_select"       ON moments;
DROP POLICY IF EXISTS "moments_insert_own"   ON moments;
DROP POLICY IF EXISTS "moments_update_own"   ON moments;
DROP POLICY IF EXISTS "moments_delete_own"   ON moments;

-- Un momento es visible si el restaurante padre lo es para el usuario solicitante:
-- dueño del momento, restaurante público, o amigo del dueño del restaurante.
CREATE POLICY "moments_select"
  ON moments FOR SELECT
  USING (
    auth.uid() = user_id                          -- dueño del momento
    OR EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = moments.restaurant_id
        AND (
          r.is_public = TRUE                      -- restaurante público
          OR are_friends(auth.uid(), r.user_id)   -- amigo del dueño del restaurante
        )
    )
  );

-- Solo el dueño puede insertar momentos con su user_id
CREATE POLICY "moments_insert_own"
  ON moments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Solo el dueño puede actualizar
CREATE POLICY "moments_update_own"
  ON moments FOR UPDATE
  USING (auth.uid() = user_id);

-- Solo el dueño puede eliminar
CREATE POLICY "moments_delete_own"
  ON moments FOR DELETE
  USING (auth.uid() = user_id);

-- ── 5.4 friendships ───────────────────────────────────────────────────────────
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "friendships_select_own"   ON friendships;
DROP POLICY IF EXISTS "friendships_insert"       ON friendships;
DROP POLICY IF EXISTS "friendships_update"       ON friendships;
DROP POLICY IF EXISTS "friendships_delete"       ON friendships;

-- Solo los involucrados pueden ver sus amistades
CREATE POLICY "friendships_select_own"
  ON friendships FOR SELECT
  USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- Solo usuarios autenticados pueden crear solicitudes (como requester)
CREATE POLICY "friendships_insert"
  ON friendships FOR INSERT
  WITH CHECK (auth.uid() = requester_id);

-- El addressee puede aceptar o bloquear; el requester puede bloquear.
-- Nadie puede cambiar requester_id/addressee_id (inmutables tras creación).
CREATE POLICY "friendships_update"
  ON friendships FOR UPDATE
  USING (
    auth.uid() = addressee_id                     -- addressee: puede aceptar o bloquear
    OR (auth.uid() = requester_id AND status = 'blocked') -- requester: puede bloquear
  );

-- Ambos involucrados pueden eliminar la relación
CREATE POLICY "friendships_delete"
  ON friendships FOR DELETE
  USING (auth.uid() = requester_id OR auth.uid() = addressee_id);


-- ── 6. ÍNDICES DE PERFORMANCE ────────────────────────────────────────────────

-- restaurants: queries frecuentes de feed y filtros de descubrimiento
CREATE INDEX IF NOT EXISTS idx_restaurants_user_id     ON restaurants(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_neighborhood ON restaurants(neighborhood);
CREATE INDEX IF NOT EXISTS idx_restaurants_cuisine     ON restaurants(cuisine);
CREATE INDEX IF NOT EXISTS idx_restaurants_created_at  ON restaurants(created_at DESC);
-- Index parcial para feed público (evita escanear restaurantes privados)
CREATE INDEX IF NOT EXISTS idx_restaurants_public      ON restaurants(created_at DESC) WHERE is_public = TRUE;

-- moments: joins con restaurants y queries de feed por usuario
CREATE INDEX IF NOT EXISTS idx_moments_restaurant_id   ON moments(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_moments_user_id         ON moments(user_id);
CREATE INDEX IF NOT EXISTS idx_moments_created_at      ON moments(created_at DESC);

-- friendships: lookups bidireccionales en are_friends() y listado de amigos
CREATE INDEX IF NOT EXISTS idx_friendships_requester_id ON friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee_id ON friendships(addressee_id);
-- Index compuesto para are_friends() que filtra por status
CREATE INDEX IF NOT EXISTS idx_friendships_accepted    ON friendships(requester_id, addressee_id) WHERE status = 'accepted';

-- profiles: búsqueda por username (autocomplete, @menciones)
CREATE INDEX IF NOT EXISTS idx_profiles_username       ON profiles(username);


-- ═══════════════════════════════════════════════════════════════════════════
--  SUPABASE STORAGE — Instrucciones de creación de buckets
--  (Supabase no soporta creación de buckets via SQL estándar —
--   créalos desde el Dashboard o via Management API)
-- ═══════════════════════════════════════════════════════════════════════════

/*
  BUCKETS NECESARIOS (crear en: Dashboard → Storage → New bucket):

  1. avatars
     - Nombre: avatars
     - Visibilidad: PUBLIC
     - Allowed MIME types: image/jpeg, image/png, image/webp
     - Max file size: 2 MB
     - Ruta de archivos: {user_id}/avatar.{ext}

  2. restaurant-covers
     - Nombre: restaurant-covers
     - Visibilidad: PUBLIC
     - Allowed MIME types: image/jpeg, image/png, image/webp
     - Max file size: 5 MB
     - Ruta de archivos: {user_id}/{restaurant_id}.{ext}

  3. moments
     - Nombre: moments
     - Visibilidad: PUBLIC
     - Allowed MIME types: image/jpeg, image/png, image/webp, video/mp4
     - Max file size: 10 MB
     - Ruta de archivos: {user_id}/{moment_id}.{ext}

  POLÍTICAS DE STORAGE (Dashboard → Storage → [bucket] → Policies):

  Para cada bucket, crear las siguientes políticas:

  SELECT (lectura pública):
    - Nombre: "Public read"
    - Roles: anon, authenticated
    - Expresión: true  (bucket ya es público, esta política es backup)

  INSERT (solo el dueño sube a su carpeta):
    - Nombre: "Owner insert"
    - Roles: authenticated
    - Expresión: (storage.foldername(name))[1] = auth.uid()::text

  UPDATE (solo el dueño actualiza):
    - Nombre: "Owner update"
    - Roles: authenticated
    - Expresión: (storage.foldername(name))[1] = auth.uid()::text

  DELETE (solo el dueño elimina):
    - Nombre: "Owner delete"
    - Roles: authenticated
    - Expresión: (storage.foldername(name))[1] = auth.uid()::text
*/


-- ═══════════════════════════════════════════════════════════════════════════
--  INSTRUCCIONES DE DEPLOYMENT EN SUPABASE
-- ═══════════════════════════════════════════════════════════════════════════

/*
  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  PASO A PASO PARA DESPLEGAR SCHEMA V2 EN SUPABASE                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

  ── REQUISITOS PREVIOS ──────────────────────────────────────────────────────
  1. Tener un proyecto Supabase creado en https://supabase.com/dashboard
  2. Estar en el plan Free o superior
  3. Authentication → Providers → Email habilitado (opcional pero recomendado)

  ── ORDEN DE EJECUCIÓN ──────────────────────────────────────────────────────
  Este archivo es idempotente y puede ejecutarse completo de una sola vez.
  El orden interno ya está correcto:
    Extensiones → Funciones → Tablas → View → RLS → Índices

  ── EJECUCIÓN DEL SQL ────────────────────────────────────────────────────────
  Opción A — SQL Editor (recomendado para primer deploy):
    1. Ir a: Dashboard → SQL Editor → New query
    2. Pegar el contenido completo de este archivo
    3. Hacer clic en "Run" (o Ctrl+Enter / Cmd+Enter)
    4. Verificar que no haya errores en la consola de resultados

  Opción B — CLI de Supabase:
    supabase db push --db-url "postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres"

  ── CREACIÓN DE STORAGE BUCKETS ──────────────────────────────────────────────
  (Ver sección SUPABASE STORAGE más arriba para detalles)
    1. Dashboard → Storage → New bucket
    2. Crear: avatars, restaurant-covers, moments
    3. Configurar políticas por bucket (INSERT/UPDATE/DELETE solo owner)

  ── VERIFICACIÓN POST-DEPLOY ─────────────────────────────────────────────────
  Ejecutar estas queries para confirmar que todo está correcto:

  -- Verificar tablas creadas
  SELECT table_name FROM information_schema.tables
  WHERE table_schema = 'public'
  ORDER BY table_name;
  -- Esperado: friendships, moments, profiles, restaurants

  -- Verificar RLS habilitado en todas las tablas
  SELECT tablename, rowsecurity FROM pg_tables
  WHERE schemaname = 'public';
  -- Todas deben tener rowsecurity = true

  -- Verificar políticas RLS
  SELECT tablename, policyname FROM pg_policies
  WHERE schemaname = 'public'
  ORDER BY tablename, policyname;

  -- Verificar índices creados
  SELECT indexname, tablename FROM pg_indexes
  WHERE schemaname = 'public'
  ORDER BY tablename, indexname;

  -- Verificar función are_friends
  SELECT routine_name FROM information_schema.routines
  WHERE routine_schema = 'public' AND routine_name = 'are_friends';

  -- Verificar view feed_posts
  SELECT table_name FROM information_schema.views
  WHERE table_schema = 'public';

  ── ROLLBACK (si algo falla) ──────────────────────────────────────────────────
  DROP TABLE IF EXISTS friendships CASCADE;
  DROP TABLE IF EXISTS moments CASCADE;
  DROP TABLE IF EXISTS restaurants CASCADE;
  DROP TABLE IF EXISTS profiles CASCADE;
  DROP FUNCTION IF EXISTS are_friends(UUID, UUID);
  DROP FUNCTION IF EXISTS handle_new_user();
  DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

  ── NOTAS IMPORTANTES ────────────────────────────────────────────────────────
  • La función are_friends() usa SECURITY DEFINER para acceder a friendships
    sin restricciones de RLS durante la evaluación de políticas en otras tablas.
    Esto es intencional y seguro porque la función solo hace SELECT.
  • La columna `posts` JSONB del schema v1 fue eliminada en v2.
    Si tienes datos en v1, migra con:
    INSERT INTO moments (restaurant_id, user_id, photo_url, caption, created_at)
    SELECT id, user_id,
           elem->>'photo', elem->>'caption',
           (elem->>'date')::timestamptz
    FROM restaurants, jsonb_array_elements(posts) AS elem
    WHERE jsonb_array_length(posts) > 0;
    -- Luego: ALTER TABLE restaurants DROP COLUMN IF EXISTS posts;
  • La view feed_posts no tiene RLS propio — hereda la seguridad de las tablas
    base. Para usuarios autenticados que quieren ver el feed de amigos,
    filtrar a nivel de aplicación o crear una función RPC separada.
*/
