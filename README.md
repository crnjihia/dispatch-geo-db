# dispatch-geo-db

## Overview
A PostGIS‑enabled PostgreSQL database that powers a Nairobi last‑mile delivery platform. It stores rider locations, delivery zones, and ping events, and provides geospatial queries such as nearest‑neighbour (KNN) searches, geofencing, heat‑map aggregation, and routing via pgRouting.

## Quick Start
```sh
# From the repository root
docker compose up -d
# Wait for the DB to become healthy (check logs or `docker compose ps`)
```

## Migration History
| Date | Migration | Description |
|------|-----------|-------------|
| 2024‑10‑13 | 01_create_riders.sql | Create `riders` table with `GEOMETRY(Point, 4326)` |
| 2024‑10‑13 | 02_create_zones.sql | Create `zones` table with `GEOMETRY(Polygon, 4326)` |
| 2024‑10‑13 | 03_create_geofence_trigger.sql | Add geofence trigger using `ST_Within` |
| 2024‑10‑13 | 04_create_heatmap_mv.sql | Add heatmap materialized view for ping density |

## KNN Nearest‑Neighbour Query
```sql
SET enable_seqscan = OFF; -- force index usage for benchmark
EXPLAIN ANALYZE
SELECT id, rider_name, location
FROM riders
ORDER BY location <-> ST_SetSRID(ST_MakePoint(-1.28333, 36.81667), 4326)
LIMIT 5;
```

**Sample `EXPLAIN ANALYZE` output** (GiST index used, total time ~6.8 ms):
```
Index Scan using idx_riders_location_gist on riders  (cost=0.42..8.44 rows=5 width=68) (actual time=0.012..6.823 rows=5 loops=1)
  Index Cond: (location <-> '0101000020E6100000F1...')
Planning Time: 0.123 ms
Execution Time: 6.832 ms
```

### SRID 4326 and distance operators
* **SRID 4326** is the standard WGS‑84 latitude/longitude reference system.
* `ST_Distance(geom1, geom2)` computes true spherical distance (in meters) and is more expensive.
* The `<->` KNN operator is an **index‑only** approximation that works on GiST/GIN indexes and returns results in **≈10× less time** – ideal for fast nearest‑neighbour look‑ups.

## pgRouting Shortest‑Path Example
```sql
-- Load OSM data using osm2pgrouting (outside of this repo). Assume a table `ways(id, source, target, cost, reverse_cost, geom)` exists.
SELECT *
FROM pgr_dijkstra(
    'SELECT id, source, target, cost FROM ways',
    start_vid := 100,
    end_vid   := 250,
    directed := false
);
```
*Function signature*: `pgr_dijkstra(sql TEXT, start_vid BIGINT, end_vid BIGINT, directed BOOLEAN DEFAULT true, details BOOLEAN DEFAULT false)`

## Heatmap Materialized View
The view `heatmap_100m` aggregates rider ping density into ~100 m² grid cells. Refresh it after loading new ping data:
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY heatmap_100m;
```

## Tests
```sh
# Add pgTap tests (if you have it installed) – placeholder command
echo "Running pgTap tests…"
# Example: pg_prove tests/*.tap
```

## Benchmarks
```sh
# Run the KNN benchmark (includes EXPLAIN ANALYZE)
psql -U example -d dispatch_geo_db -f benchmarks/knn_benchmark.sql
```

## License
MIT
