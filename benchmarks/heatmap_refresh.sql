-- heatmap_refresh.sql
-- Refresh the heatmap materialized view and show row count.
REFRESH MATERIALIZED VIEW CONCURRENTLY heatmap_100m;
SELECT COUNT(*) AS cell_count FROM heatmap_100m;
