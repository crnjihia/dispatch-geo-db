-- 05_create_rider_pings.sql
-- Table to store rider location pings used by the geofence trigger and heatmap MV.
CREATE TABLE IF NOT EXISTS rider_pings (
    id SERIAL PRIMARY KEY,
    rider_id INT NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
    ping_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    location GEOMETRY(Point, 4326) NOT NULL
);
