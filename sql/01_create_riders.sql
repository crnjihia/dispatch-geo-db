-- 01_create_riders.sql
-- Create Riders table with a geometry point column (SRID 4326)
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS riders (
    id SERIAL PRIMARY KEY,
    rider_name TEXT NOT NULL,
    location GEOMETRY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
