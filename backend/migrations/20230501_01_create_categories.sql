-- Create categories table for hierarchical node structure
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  uuid UUID NOT NULL DEFAULT gen_random_uuid(),
  parent_id INTEGER DEFAULT NULL,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  color VARCHAR(25),
  icon VARCHAR(50),
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMP WITH TIME ZONE,
  CONSTRAINT categories_parent_id_fk FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL,
  CONSTRAINT categories_slug_unique UNIQUE (slug),
  CONSTRAINT categories_uuid_unique UNIQUE (uuid)
);

-- Create index on parent_id for faster tree traversal
CREATE INDEX idx_categories_parent_id ON categories(parent_id);
CREATE INDEX idx_categories_slug ON categories(slug);

-- Create photos_categories join table for many-to-many relationship
CREATE TABLE IF NOT EXISTS photos_categories (
  photo_id INTEGER NOT NULL,
  category_id INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  PRIMARY KEY (photo_id, category_id),
  CONSTRAINT photos_categories_photo_id_fk FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
  CONSTRAINT photos_categories_category_id_fk FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
);

-- Create indexes for faster lookups
CREATE INDEX idx_photos_categories_photo_id ON photos_categories(photo_id);
CREATE INDEX idx_photos_categories_category_id ON photos_categories(category_id);

-- Create category_metadata table for extensible properties
CREATE TABLE IF NOT EXISTS category_metadata (
  category_id INTEGER NOT NULL,
  key VARCHAR(255) NOT NULL,
  value TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  PRIMARY KEY (category_id, key),
  CONSTRAINT category_metadata_category_id_fk FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
);

-- Add audit trigger functions for updated_at
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updating timestamps
CREATE TRIGGER update_categories_timestamp
BEFORE UPDATE ON categories
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_category_metadata_timestamp
BEFORE UPDATE ON category_metadata
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();
