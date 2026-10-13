-- 03_create_geofence_trigger.sql
-- 1. Table to store rider location pings
CREATE TABLE IF NOT EXISTS rider_pings (
    id SERIAL PRIMARY KEY,
    rider_id INT NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
    ping_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    location GEOMETRY(Point, 4326) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rider_pings_location_gist ON rider_pings USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_rider_pings_rider_time ON rider_pings (rider_id, ping_at DESC);

-- 2. Table to store geofence enter/exit events
CREATE TABLE IF NOT EXISTS zone_events (
    id SERIAL PRIMARY KEY,
    rider_id INT NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
    zone_id INT NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('enter', 'exit')),
    event_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zone_events_rider_time ON zone_events (rider_id, event_at DESC);

-- 3. Geofencing trigger function
CREATE OR REPLACE FUNCTION log_geofence_event() RETURNS TRIGGER AS $$
DECLARE
    prev_loc GEOMETRY(Point, 4326);
    zone_rec RECORD;
    was_inside BOOLEAN;
    is_inside BOOLEAN;
BEGIN
    -- Retrieve rider's immediate previous ping location
    SELECT location INTO prev_loc
    FROM rider_pings
    WHERE rider_id = NEW.rider_id AND id != NEW.id
    ORDER BY ping_at DESC, id DESC
    LIMIT 1;

    -- Evaluate only zones that could be entered or exited
    FOR zone_rec IN
        SELECT id, boundary
        FROM zones
        WHERE ST_Within(NEW.location, boundary)
           OR (prev_loc IS NOT NULL AND ST_Within(prev_loc, boundary))
    LOOP
        is_inside := ST_Within(NEW.location, zone_rec.boundary);
        was_inside := (prev_loc IS NOT NULL AND ST_Within(prev_loc, zone_rec.boundary));

        IF is_inside AND NOT was_inside THEN
            INSERT INTO zone_events (rider_id, zone_id, event_type, event_at)
            VALUES (NEW.rider_id, zone_rec.id, 'enter', NEW.ping_at);
        ELSIF was_inside AND NOT is_inside THEN
            INSERT INTO zone_events (rider_id, zone_id, event_type, event_at)
            VALUES (NEW.rider_id, zone_rec.id, 'exit', NEW.ping_at);
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Attach trigger
DROP TRIGGER IF EXISTS rider_geofence_trigger ON rider_pings;
CREATE TRIGGER rider_geofence_trigger
AFTER INSERT ON rider_pings
FOR EACH ROW EXECUTE FUNCTION log_geofence_event();
