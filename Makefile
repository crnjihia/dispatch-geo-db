.PHONY: up down test bench

up:
	docker compose up -d

down:
	docker compose down

test:
	# Run pgTap tests (requires pgTap installed)
	docker compose exec -T db pg_prove /tests/*.tap

bench:
	# KNN benchmark
	docker compose exec -T db psql -U example -d dispatch_geo_db -f /benchmarks/knn_benchmark.sql
	# Refresh heatmap materialized view
	docker compose exec -T db psql -U example -d dispatch_geo_db -c "REFRESH MATERIALIZED VIEW CONCURRENTLY heatmap_100m;"
