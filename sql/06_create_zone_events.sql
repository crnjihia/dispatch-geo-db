-- 06_create_zone_events.sql
-- Table that logs entry/exit events produced by the geofence trigger.
CREATE TABLE IF NOT EXISTS zone_events (
    id SERIAL PRIMARY KEY,
    rider_id INT NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
    zone_id INT NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('enter','exit')),
    event_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
