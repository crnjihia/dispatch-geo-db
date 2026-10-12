-- 04_create_heatmap_mv.sql
-- Materialized view that aggregates rider ping density per 100m² grid cell.
-- Assumes a table rider_pings(id SERIAL, rider_id INT, ping_at TIMESTAMPTZ, location GEOMETRY(Point, 4326)).

CREATE MATERIALIZED VIEW IF NOT EXISTS heatmap_100m AS
SELECT
    ST_SnapToGrid(location, 0.0009) AS grid_cell, -- approx 100m at lat 0 (adjust as needed)
    COUNT(*) AS ping_count
FROM rider_pings
GROUP BY grid_cell;

-- Refresh view automatically every hour (optional cron here, or manual REFRESH MATERIALIZED VIEW).
