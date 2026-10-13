-- 04_create_heatmap_mv.sql
-- Seed sample rider pings to populate heatmap and exercise the geofence trigger
INSERT INTO rider_pings (rider_id, location, ping_at) VALUES
    (1, ST_SetSRID(ST_MakePoint(36.82194, -1.28639), 4326), now() - INTERVAL '30 minutes'),
    (1, ST_SetSRID(ST_MakePoint(36.82250, -1.28650), 4326), now() - INTERVAL '20 minutes'),
    (1, ST_SetSRID(ST_MakePoint(36.82310, -1.28670), 4326), now() - INTERVAL '10 minutes'),
    (2, ST_SetSRID(ST_MakePoint(36.80550, -1.26350), 4326), now() - INTERVAL '25 minutes'),
    (2, ST_SetSRID(ST_MakePoint(36.80620, -1.26400), 4326), now() - INTERVAL '15 minutes'),
    (3, ST_SetSRID(ST_MakePoint(36.78500, -1.29210), 4326), now() - INTERVAL '20 minutes'),
    (4, ST_SetSRID(ST_MakePoint(36.81500, -1.29800), 4326), now() - INTERVAL '15 minutes');

-- Additional distributed pings across Nairobi for dense heatmap clustering
INSERT INTO rider_pings (rider_id, location, ping_at)
SELECT
    (1 + (i % 10)),
    ST_SetSRID(
        ST_MakePoint(
            36.80 + ((i % 50) * 0.001),
            -1.30 + ((i % 50) * 0.001)
        ),
        4326
    ),
    now() - (i || ' seconds')::INTERVAL
FROM generate_series(1, 200) AS i;

-- Heatmap materialized view aggregating ping density per ~100m² grid cell
CREATE MATERIALIZED VIEW IF NOT EXISTS heatmap_100m AS
SELECT
    ST_SnapToGrid(location, 0.0009) AS grid_cell, -- approx 100m at equator
    COUNT(*) AS ping_count
FROM rider_pings
GROUP BY grid_cell;

-- Unique index required for REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_heatmap_100m_grid_cell ON heatmap_100m (grid_cell);

-- pgRouting ways network schema and sample Nairobi topology
CREATE TABLE IF NOT EXISTS ways (
    id SERIAL PRIMARY KEY,
    source BIGINT NOT NULL,
    target BIGINT NOT NULL,
    cost DOUBLE PRECISION NOT NULL,
    reverse_cost DOUBLE PRECISION NOT NULL,
    name TEXT,
    geom GEOMETRY(LineString, 4326)
);

CREATE INDEX IF NOT EXISTS idx_ways_source ON ways(source);
CREATE INDEX IF NOT EXISTS idx_ways_target ON ways(target);
CREATE INDEX IF NOT EXISTS idx_ways_geom_gist ON ways USING GIST (geom);

-- Seed sample connected road network representing key Nairobi corridors
-- Node 1: CBD (Moi Ave), Node 2: CBD North (University Way), Node 3: Westlands,
-- Node 4: Upper Hill, Node 5: Kilimani
INSERT INTO ways (id, source, target, cost, reverse_cost, name, geom) VALUES
    (1, 1, 2, 1050.0, 1050.0, 'Kenyatta Ave / Moi Ave',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(36.824, -1.288), ST_MakePoint(36.818, -1.280)), 4326)),
    (2, 2, 3, 2100.0, 2100.0, 'Waiyaki Way (CBD - Westlands)',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(36.818, -1.280), ST_MakePoint(36.808, -1.265)), 4326)),
    (3, 1, 4, 1500.0, 1500.0, 'Uhuru Highway / Haile Selassie',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(36.824, -1.288), ST_MakePoint(36.815, -1.298)), 4326)),
    (4, 4, 5, 3300.0, 3300.0, 'Ngong Rd / Argwings Kodhek',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(36.815, -1.298), ST_MakePoint(36.786, -1.294)), 4326)),
    (5, 3, 5, 3800.0, 3800.0, 'Ring Rd Kilimani / Westlands',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(36.808, -1.265), ST_MakePoint(36.786, -1.294)), 4326)),
    (6, 2, 4, 2200.0, 2200.0, 'Kenyatta Ave to Upper Hill Link',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(36.818, -1.280), ST_MakePoint(36.815, -1.298)), 4326))
ON CONFLICT (id) DO NOTHING;

-- Synchronize sequence
SELECT setval('ways_id_seq', (SELECT MAX(id) FROM ways));
