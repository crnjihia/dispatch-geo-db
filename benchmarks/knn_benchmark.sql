-- knn_benchmark.sql
-- Benchmark for nearest-neighbour rider search (5 closest available riders to Nairobi CBD).
-- Coordinates: Longitude 36.81667, Latitude -1.28333 (Nairobi city centre)

SET enable_seqscan = OFF; -- verify index scan performance

EXPLAIN ANALYZE
SELECT id, rider_name, location
FROM riders
ORDER BY location <-> ST_SetSRID(ST_MakePoint(36.81667, -1.28333), 4326)
LIMIT 5;
