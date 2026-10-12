-- 07_create_ways.sql
-- Placeholder for pgRouting network data. Populate with osm2pgrouting.
CREATE TABLE IF NOT EXISTS ways (
    id SERIAL PRIMARY KEY,
    source BIGINT,
    target BIGINT,
    cost DOUBLE PRECISION,
    reverse_cost DOUBLE PRECISION,
    geom GEOMETRY(LineString, 4326)
);
