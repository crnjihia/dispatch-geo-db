-- 02_create_zones.sql
-- Create Zones table with a polygon geometry column (SRID 4326)
CREATE TABLE IF NOT EXISTS zones (
    id SERIAL PRIMARY KEY,
    zone_name TEXT NOT NULL,
    boundary GEOMETRY(Polygon, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- GiST spatial index on zone boundaries for fast ST_Within evaluation
CREATE INDEX IF NOT EXISTS idx_zones_boundary_gist ON zones USING GIST (boundary);

-- Seed representative Nairobi delivery zones
INSERT INTO zones (zone_name, boundary) VALUES
    (
        'Nairobi CBD',
        ST_SetSRID(
            ST_PolygonFromText('POLYGON((36.8140 -1.2820, 36.8280 -1.2820, 36.8280 -1.2920, 36.8140 -1.2920, 36.8140 -1.2820))'),
            4326
        )
    ),
    (
        'Westlands',
        ST_SetSRID(
            ST_PolygonFromText('POLYGON((36.7950 -1.2550, 36.8180 -1.2550, 36.8180 -1.2720, 36.7950 -1.2720, 36.7950 -1.2550))'),
            4326
        )
    ),
    (
        'Kilimani',
        ST_SetSRID(
            ST_PolygonFromText('POLYGON((36.7720 -1.2850, 36.7950 -1.2850, 36.7950 -1.3050, 36.7720 -1.3050, 36.7720 -1.2850))'),
            4326
        )
    ),
    (
        'Upper Hill',
        ST_SetSRID(
            ST_PolygonFromText('POLYGON((36.8080 -1.2920, 36.8250 -1.2920, 36.8250 -1.3080, 36.8080 -1.3080, 36.8080 -1.2920))'),
            4326
        )
    );

