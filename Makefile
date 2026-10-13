.PHONY: up down restart test bench psql logs

up:
	docker compose up -d

down:
	docker compose down -v

restart: down up

test:
	docker compose exec -T db psql -U example -d dispatch_geo_db -f /tests/test_suite.sql

bench:
	docker compose exec -T db psql -U example -d dispatch_geo_db -f /benchmarks/knn_benchmark.sql
	docker compose exec -T db psql -U example -d dispatch_geo_db -f /benchmarks/heatmap_refresh.sql

psql:
	docker compose exec -it db psql -U example -d dispatch_geo_db

logs:
	docker compose logs -f db
