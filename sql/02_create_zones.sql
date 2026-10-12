-- 02_create_zones.sql
-- Create Zones table with a polygon geometry column (SRID 4326)
CREATE TABLE IF NOT EXISTS zones (
    id SERIAL PRIMARY KEY,
    zone_name TEXT NOT NULL,
    boundary GEOMETRY(Polygon, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
