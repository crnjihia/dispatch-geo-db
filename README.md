# Dispatch Geo DB

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-blue.svg)](https://www.postgresql.org/)
[![PostGIS](https://img.shields.io/badge/PostGIS-3.5-green.svg)](https://postgis.net/)
[![pgRouting](https://img.shields.io/badge/pgRouting-3.7-orange.svg)](https://pgrouting.org/)

A production-grade, PostGIS and pgRouting spatial database engineered for a last-mile delivery and dispatch platform operating in Nairobi, Kenya.

This system demonstrates geospatial indexing, high-throughput nearest-neighbour (KNN) rider dispatch, automated geofencing triggers, ping density heatmap aggregation, and turn-by-turn road network shortest-path routing.

---

## Architecture & Schema Overview

```
                                  +-------------------+
                                  |       zones       |
                                  |  (Polygon, 4326)  |
                                  +---------+---------+
                                            |
                                  ST_Within | Geofence Trigger
                                            v
+------------------+              +-------------------+
|      riders      |              |    zone_events    |
|   (Point, 4326)  |              |   (enter / exit)  |
+--------+---------+              +-------------------+
         |                                  ^
         | 1:N                              |
         v                                  |
+------------------+                        |
|   rider_pings    |------------------------+
|   (Point, 4326)  |
+--------+---------+
         |
         | ST_SnapToGrid (0.0009 deg ≈ 100m)
         v
+---------------------------+     +-------------------+
|       heatmap_100m        |     |       ways        |
|    (Materialized View)    |     | (LineString, 4326)|
+---------------------------+     +---------+---------+
                                            |
                                            | pgr_dijkstra()
                                            v
                                    Shortest Delivery
                                         Routing
```

### Core Schema Files (`sql/`)

| Script | Object | Description |
|---|---|---|
| `sql/01_create_riders.sql` | `riders` | PostGIS point geometry (`GEOMETRY(Point, 4326)`) with GiST spatial indexing and seed Nairobi riders. |
| `sql/02_create_zones.sql` | `zones` | Delivery boundary polygons (`GEOMETRY(Polygon, 4326)`) with GiST index and polygons for CBD, Westlands, Kilimani, and Upper Hill. |
| `sql/03_create_geofence_trigger.sql` | `rider_pings`, `zone_events`, `log_geofence_event()` | Real-time geofence transition trigger (`ST_Within`) logging `enter` and `exit` events without duplicates. |
| `sql/04_create_heatmap_mv.sql` | `heatmap_100m`, `ways` | Spatial grid cell density aggregation with unique index for concurrent refresh, plus pgRouting arterial topology. |

---

## Quick Start

### 1. Start the Database Container

```bash
docker compose up -d
```

PostgreSQL 17 with PostGIS 3.5 and pgRouting 3.7 will initialize all schemas, seed data, indexes, and triggers automatically. Verify container health:

```bash
docker compose ps
```

### 2. Run Integration Tests

```bash
docker compose exec -T db psql -U example -d dispatch_geo_db -f /tests/test_suite.sql
```

### 3. Run KNN & Heatmap Benchmarks

```bash
docker compose exec -T db psql -U example -d dispatch_geo_db -f /benchmarks/knn_benchmark.sql
docker compose exec -T db psql -U example -d dispatch_geo_db -f /benchmarks/heatmap_refresh.sql
```

---

## 1. KNN Rider Dispatch Query (`<->` Operator)

To match incoming customer orders with the 5 closest available delivery riders in real time, the platform uses the PostGIS `<->` distance operator backed by an R-Tree GiST spatial index.

### Query Definition

```sql
SET enable_seqscan = OFF;

EXPLAIN ANALYZE
SELECT id, rider_name, location
FROM riders
ORDER BY location <-> ST_SetSRID(ST_MakePoint(36.81667, -1.28333), 4326)
LIMIT 5;
```

### Reproducible `EXPLAIN ANALYZE` Output

Executed on a dataset of 1,000 riders across Nairobi:

```
                                                                 QUERY PLAN                                                                 
--------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.14..3.75 rows=5 width=76) (actual time=0.207..0.222 rows=5 loops=1)
   ->  Index Scan using idx_riders_location_gist on riders  (cost=0.14..619.41 rows=858 width=76) (actual time=0.206..0.220 rows=5 loops=1)
         Order By: (location <-> '0101000020E6100000EACF7EA488684240639CBF098588F4BF'::geometry)
 Planning Time: 5.563 ms
 Execution Time: 0.259 ms
(5 rows)
```

**Key Observation:** The query executes in **0.259 ms (well under the 10 ms threshold)** via an index scan on `idx_riders_location_gist`.

---

## 2. Spatial Indexing Notes: SRID 4326 vs Distance Operators

### SRID 4326 (WGS 84)

- **SRID 4326** represents spatial coordinates using the WGS 84 ellipsoid, where geometries are stored as **(longitude, latitude)** in decimal degrees.
- In PostGIS, `ST_MakePoint(x, y)` corresponds to `ST_MakePoint(longitude, latitude)`. Inverting the coordinates (e.g., placing latitude first) places points on an entirely wrong continent.

### Difference Between `ST_Distance` and `<->`

| Characteristic | `ST_Distance(geom1, geom2)` | PostGIS `<->` Operator |
|---|---|---|
| **Mechanism** | Exact distance calculation (planar degrees or spheroidal meters via `geography`). | Bounding-box centroid distance evaluation directly supported by GiST R-Tree index. |
| **Index Traversal** | **Cannot utilize index-driven ordering.** Requires evaluating every candidate row (O(N) sequential scan). | **Index-driven KNN.** Traverses GiST tree nodes with a priority queue (O(log N)), terminating immediately after finding top $k$ items. |
| **Dispatch Performance** | Scales linearly with rider count (50–200 ms on large fleets). | Constant sub-millisecond execution (< 1 ms). |
| **Recommended Usage** | Exact filtering within a radius (`ST_DWithin`) or computing billing distances. | Real-time nearest-neighbour ranking (`ORDER BY ... LIMIT k`). |

---

## 3. Automated Geofencing Trigger

Riders report GPS pings into `rider_pings`. An `AFTER INSERT` trigger (`log_geofence_event`) checks zone transitions using `ST_Within(point, polygon)` and maintains a clean log in `zone_events`:

1. **Enter Event:** Rider's previous ping was outside the zone, and the current ping is inside (`ST_Within(NEW.location, zone.boundary)` is TRUE).
2. **Stay (No Event):** Rider's previous ping and current ping are both inside the zone. Duplicate enter events are avoided.
3. **Exit Event:** Rider's previous ping was inside the zone, and the current ping has moved outside.

```sql
CREATE OR REPLACE FUNCTION log_geofence_event() RETURNS TRIGGER AS $$
DECLARE
    prev_loc GEOMETRY(Point, 4326);
    zone_rec RECORD;
    was_inside BOOLEAN;
    is_inside BOOLEAN;
BEGIN
    SELECT location INTO prev_loc
    FROM rider_pings
    WHERE rider_id = NEW.rider_id AND id != NEW.id
    ORDER BY ping_at DESC, id DESC
    LIMIT 1;

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
```

---

## 4. Heatmap Materialized View (~100m² Grid Cells)

To visualize rider density and identify underserviced zones, the materialized view `heatmap_100m` aggregates pings into 100m² grid cells:

$$\Delta\text{deg} \approx \frac{100\text{ m}}{111{,}000\text{ m/deg}} \approx 0.0009^\circ$$

```sql
CREATE MATERIALIZED VIEW heatmap_100m AS
SELECT
    ST_SnapToGrid(location, 0.0009) AS grid_cell,
    COUNT(*) AS ping_count
FROM rider_pings
GROUP BY grid_cell;

-- Enables zero-downtime background refresh
CREATE UNIQUE INDEX idx_heatmap_100m_grid_cell ON heatmap_100m (grid_cell);
```

Concurrent refresh can be executed without locking reads:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY heatmap_100m;
```

---

## 5. pgRouting: Shortest-Path Delivery Routing

### pgRouting Dijkstra Signature

```sql
pgr_dijkstra(
    edges_sql TEXT,
    start_vid BIGINT,
    end_vid BIGINT,
    directed BOOLEAN DEFAULT true
)
RETURNS TABLE (
    seq INT,
    path_seq INT,
    node BIGINT,
    edge BIGINT,
    cost DOUBLE PRECISION,
    agg_cost DOUBLE PRECISION
);
```

### Demonstration Query

Route from **Nairobi CBD (Node 1)** to **Kilimani Delivery Hub (Node 5)**:

```sql
SELECT
    seq,
    node,
    edge,
    cost,
    agg_cost
FROM pgr_dijkstra(
    'SELECT id, source, target, cost, reverse_cost FROM ways',
    1,
    5,
    directed := false
);
```

**Result:**

```
 seq | node | edge | cost | agg_cost 
-----+------+------+------+----------
   1 |    1 |    3 | 1500 |        0
   2 |    4 |    4 | 3300 |     1500
   3 |    5 |   -1 |    0 |     4800
(3 rows)
```

Path: CBD (Node 1) $\rightarrow$ Upper Hill (Node 4) via Uhuru Highway $\rightarrow$ Kilimani (Node 5) via Argwings Kodhek (Total distance: 4,800 meters).

---

## 6. OpenStreetMap (OSM) Ingestion

To load the full Nairobi road network from OpenStreetMap into the `ways` table:

1. Download a Nairobi extract from [Geofabrik](https://download.geofabrik.de/africa/kenya.html) or [BBBike](https://extract.bbbike.org/):
   ```bash
   curl -Lo data/nairobi.osm.pbf https://download.geofabrik.de/africa/kenya-latest.osm.pbf
   ```

2. Run `osm2pgrouting` to parse ways and build topological vertices:
   ```bash
   docker run --rm -v "$(pwd)/data:/data" \
       -e PGPASSWORD=postgres \
       --network host \
       pgrouting/pgrouting:latest \
       osm2pgrouting -f /data/nairobi.osm.pbf \
           -c /usr/share/osm2pgrouting/mapconfig.xml \
           -d dispatch_geo_db \
           -U example \
           -W postgres \
           -p 5436 \
           --clean
   ```

---

## 7. Make Shortcuts

| Command | Action |
|---|---|
| `make up` | Start PostGIS/pgRouting container in the background. |
| `make down` | Tear down database and prune volumes. |
| `make test` | Run full schema, trigger, and routing test suite. |
| `make bench` | Run KNN EXPLAIN ANALYZE benchmark and heatmap refresh. |
| `make psql` | Open interactive `psql` console into `dispatch_geo_db`. |

---

## License

MIT
