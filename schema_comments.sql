-- Tabla de comentarios
CREATE TABLE IF NOT EXISTS comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (char_length(content) <= 280),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

-- Ver comentarios: cualquiera puede ver comentarios de restaurantes públicos
CREATE POLICY "Ver comentarios públicos" ON comments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = restaurant_id AND r.is_public = true
    )
  );

-- Crear comentario: solo usuarios autenticados
CREATE POLICY "Crear comentario" ON comments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Borrar propio comentario
CREATE POLICY "Borrar propio comentario" ON comments
  FOR DELETE USING (auth.uid() = user_id);

-- Index para performance
CREATE INDEX IF NOT EXISTS comments_restaurant_id_idx ON comments(restaurant_id);
CREATE INDEX IF NOT EXISTS comments_created_at_idx ON comments(created_at DESC);
