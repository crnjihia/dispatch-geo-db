-- knn_benchmark.sql
-- Benchmark for nearest‑neighbour rider search (5 closest riders).
-- Adjust the longitude/latitude values as needed for the test.

SET enable_seqscan = OFF; -- encourage index usage for benchmark clarity

EXPLAIN ANALYZE
SELECT id, rider_name, location
FROM riders
ORDER BY location <-> ST_SetSRID(ST_MakePoint(-1.28333, 36.81667), 4326)
LIMIT 5;
