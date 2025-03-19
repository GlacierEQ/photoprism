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
CREATE INDEX idx_categories_deleted_at ON categories(deleted_at);
CREATE INDEX idx_categories_order_index ON categories(order_index);

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

-- Create index for faster metadata lookups
CREATE INDEX idx_category_metadata_key ON category_metadata(key);

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

-- Create categories_path table for materialized paths
CREATE TABLE IF NOT EXISTS categories_path (
  ancestor_id INTEGER NOT NULL,
  descendant_id INTEGER NOT NULL,
  depth INTEGER NOT NULL,
  PRIMARY KEY (ancestor_id, descendant_id),
  CONSTRAINT categories_path_ancestor_fk FOREIGN KEY (ancestor_id) REFERENCES categories(id) ON DELETE CASCADE,
  CONSTRAINT categories_path_descendant_fk FOREIGN KEY (descendant_id) REFERENCES categories(id) ON DELETE CASCADE
);

-- Create index for faster path queries
CREATE INDEX idx_categories_path_ancestor ON categories_path(ancestor_id);
CREATE INDEX idx_categories_path_descendant ON categories_path(descendant_id);
CREATE INDEX idx_categories_path_depth ON categories_path(depth);

-- Create triggers to maintain the path table
CREATE OR REPLACE FUNCTION maintain_categories_path()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Insert self-reference path
    INSERT INTO categories_path (ancestor_id, descendant_id, depth)
    VALUES (NEW.id, NEW.id, 0);

    -- If parent exists, copy paths from parent and increment depth
    IF NEW.parent_id IS NOT NULL THEN
      INSERT INTO categories_path (ancestor_id, descendant_id, depth)
      SELECT ancestor_id, NEW.id, depth + 1
      FROM categories_path
      WHERE descendant_id = NEW.parent_id;
    END IF;

  ELSIF TG_OP = 'UPDATE' AND OLD.parent_id IS DISTINCT FROM NEW.parent_id THEN
    -- Delete paths where this node is a descendant except self-reference
    DELETE FROM categories_path
    WHERE descendant_id = NEW.id AND ancestor_id != NEW.id;

    -- If new parent exists, copy paths from new parent and increment depth
    IF NEW.parent_id IS NOT NULL THEN
      INSERT INTO categories_path (ancestor_id, descendant_id, depth)
      SELECT ancestor_id, NEW.id, depth + 1
      FROM categories_path
      WHERE descendant_id = NEW.parent_id;
    END IF;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER maintain_categories_path_trigger
AFTER INSERT OR UPDATE OF parent_id ON categories
FOR EACH ROW
EXECUTE FUNCTION maintain_categories_path();
