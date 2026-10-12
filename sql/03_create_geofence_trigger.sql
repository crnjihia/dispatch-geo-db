-- 03_create_geofence_trigger.sql
-- Trigger that logs entry/exit events when a rider ping falls inside a zone.
-- Assumes a table rider_pings(id SERIAL, rider_id INT, ping_at TIMESTAMPTZ, location GEOMETRY(Point, 4326)).
-- And a table zone_events(id SERIAL, rider_id INT, zone_id INT, event_type TEXT, event_at TIMESTAMPTZ).

CREATE OR REPLACE FUNCTION log_geofence_event() RETURNS TRIGGER AS $$
DECLARE
    zone_rec RECORD;
BEGIN
    FOR zone_rec IN SELECT id, boundary FROM zones LOOP
        IF ST_Within(NEW.location, zone_rec.boundary) THEN
            INSERT INTO zone_events (rider_id, zone_id, event_type, event_at)
            VALUES (NEW.rider_id, zone_rec.id, 'enter', now());
        ELSE
            INSERT INTO zone_events (rider_id, zone_id, event_type, event_at)
            VALUES (NEW.rider_id, zone_rec.id, 'exit', now());
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER rider_geofence_trigger
AFTER INSERT ON rider_pings
FOR EACH ROW EXECUTE FUNCTION log_geofence_event();
