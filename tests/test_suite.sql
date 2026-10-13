-- tests/test_suite.sql
-- Integration test suite for dispatch-geo-db
\set ON_ERROR_STOP on

BEGIN;

-- 1. Test extensions
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM pg_extension WHERE extname = 'postgis') = 1, 'PostGIS extension missing';
    ASSERT (SELECT count(*) FROM pg_extension WHERE extname = 'pgrouting') = 1, 'pgRouting extension missing';
    RAISE NOTICE 'PASS: PostGIS and pgRouting extensions active.';
END $$;

-- 2. Test tables and spatial columns
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM information_schema.tables WHERE table_name = 'riders') = 1, 'riders table missing';
    ASSERT (SELECT count(*) FROM information_schema.tables WHERE table_name = 'zones') = 1, 'zones table missing';
    ASSERT (SELECT count(*) FROM information_schema.tables WHERE table_name = 'rider_pings') = 1, 'rider_pings table missing';
    ASSERT (SELECT count(*) FROM information_schema.tables WHERE table_name = 'zone_events') = 1, 'zone_events table missing';
    ASSERT (SELECT count(*) FROM information_schema.tables WHERE table_name = 'ways') = 1, 'ways table missing';
    RAISE NOTICE 'PASS: Schema tables exist.';
END $$;

-- 3. Test GiST spatial indexes
DO $$
BEGIN
    ASSERT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'riders' AND indexname = 'idx_riders_location_gist'
    ), 'GiST index on riders.location missing';

    ASSERT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'zones' AND indexname = 'idx_zones_boundary_gist'
    ), 'GiST index on zones.boundary missing';

    RAISE NOTICE 'PASS: GiST spatial indexes verified.';
END $$;

-- 4. Test KNN query operator (<->) returns exactly 5 nearest riders
DO $$
DECLARE
    rider_count INT;
BEGIN
    SELECT count(*) INTO rider_count
    FROM (
        SELECT id, rider_name, location
        FROM riders
        ORDER BY location <-> ST_SetSRID(ST_MakePoint(36.81667, -1.28333), 4326)
        LIMIT 5
    ) sub;

    ASSERT rider_count = 5, 'KNN query did not return 5 riders';
    RAISE NOTICE 'PASS: KNN 5 nearest riders search verified.';
END $$;

-- 5. Test Geofence Trigger: Enter, Stay, Exit transitions
DO $$
DECLARE
    test_rider_id INT;
    cbd_zone_id INT;
    enter_events INT;
    exit_events INT;
BEGIN
    -- Create test rider
    INSERT INTO riders (rider_name, location)
    VALUES ('Test Geofence Rider', ST_SetSRID(ST_MakePoint(36.82194, -1.28639), 4326))
    RETURNING id INTO test_rider_id;

    SELECT id INTO cbd_zone_id FROM zones WHERE zone_name = 'Nairobi CBD';

    -- Ping 1: Inside CBD -> should generate 'enter'
    INSERT INTO rider_pings (rider_id, location, ping_at)
    VALUES (test_rider_id, ST_SetSRID(ST_MakePoint(36.82194, -1.28639), 4326), now() - INTERVAL '3 minutes');

    SELECT count(*) INTO enter_events
    FROM zone_events
    WHERE rider_id = test_rider_id AND zone_id = cbd_zone_id AND event_type = 'enter';

    ASSERT enter_events = 1, 'Geofence trigger failed to log enter event';

    -- Ping 2: Still inside CBD -> should NOT generate duplicate event
    INSERT INTO rider_pings (rider_id, location, ping_at)
    VALUES (test_rider_id, ST_SetSRID(ST_MakePoint(36.82200, -1.28645), 4326), now() - INTERVAL '2 minutes');

    SELECT count(*) INTO enter_events
    FROM zone_events
    WHERE rider_id = test_rider_id AND zone_id = cbd_zone_id AND event_type = 'enter';

    ASSERT enter_events = 1, 'Geofence trigger logged duplicate enter event while remaining in zone';

    -- Ping 3: Move outside CBD to unzoned coordinates (e.g., Thika Road / Roysambu 36.88, -1.21) -> should generate 'exit'
    INSERT INTO rider_pings (rider_id, location, ping_at)
    VALUES (test_rider_id, ST_SetSRID(ST_MakePoint(36.88000, -1.21000), 4326), now() - INTERVAL '1 minute');

    SELECT count(*) INTO exit_events
    FROM zone_events
    WHERE rider_id = test_rider_id AND zone_id = cbd_zone_id AND event_type = 'exit';

    ASSERT exit_events = 1, 'Geofence trigger failed to log exit event';

    RAISE NOTICE 'PASS: Geofencing enter/stay/exit transitions verified.';
END $$;

-- 6. Test Heatmap Materialized View and Concurrent Refresh
DO $$
DECLARE
    cells INT;
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY heatmap_100m;
    SELECT count(*) INTO cells FROM heatmap_100m;
    ASSERT cells > 0, 'Heatmap materialized view is empty';
    RAISE NOTICE 'PASS: Heatmap materialized view refreshed concurrently with % cells.', cells;
END $$;

-- 7. Test pgRouting Shortest Path Query (pgr_dijkstra)
DO $$
DECLARE
    path_steps INT;
    total_cost DOUBLE PRECISION;
BEGIN
    SELECT count(*), coalesce(sum(cost), 0)
    INTO path_steps, total_cost
    FROM pgr_dijkstra(
        'SELECT id, source, target, cost, reverse_cost FROM ways',
        1,  -- Nairobi CBD
        5,  -- Kilimani
        false
    );

    ASSERT path_steps > 0, 'pgRouting pgr_dijkstra returned no path';
    RAISE NOTICE 'PASS: pgRouting dijkstra path found (% segments, total cost %m).', path_steps, total_cost;
END $$;

ROLLBACK;

SELECT 'ALL TESTS PASSED SUCCESSFULLY' AS status;
