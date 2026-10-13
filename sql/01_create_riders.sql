-- 01_create_riders.sql
-- Enable PostGIS and pgRouting extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;

-- Create Riders table with a geometry point column (SRID 4326)
CREATE TABLE IF NOT EXISTS riders (
    id SERIAL PRIMARY KEY,
    rider_name TEXT NOT NULL,
    location GEOMETRY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- GiST spatial index on rider locations for high-performance KNN searches
CREATE INDEX IF NOT EXISTS idx_riders_location_gist ON riders USING GIST (location);

-- Seed realistic initial riders across Nairobi key districts
INSERT INTO riders (rider_name, location) VALUES
    ('Kipchoge Mwangi (CBD)', ST_SetSRID(ST_MakePoint(36.82194, -1.28639), 4326)),
    ('Achieng Odhiambo (Westlands)', ST_SetSRID(ST_MakePoint(36.80550, -1.26350), 4326)),
    ('Wanjiku Kamau (Kilimani)', ST_SetSRID(ST_MakePoint(36.78500, -1.29210), 4326)),
    ('Juma Omondi (Upper Hill)', ST_SetSRID(ST_MakePoint(36.81500, -1.29800), 4326)),
    ('Muthoni Kariuki (Parklands)', ST_SetSRID(ST_MakePoint(36.81800, -1.26000), 4326)),
    ('Hassan Noor (Eastleigh)', ST_SetSRID(ST_MakePoint(36.84800, -1.27500), 4326)),
    ('Chebet Korir (Karen)', ST_SetSRID(ST_MakePoint(36.71200, -1.32000), 4326)),
    ('Otieno Brian (South B)', ST_SetSRID(ST_MakePoint(36.83700, -1.31200), 4326)),
    ('Nyambura Njeri (Ngara)', ST_SetSRID(ST_MakePoint(36.82500, -1.27700), 4326)),
    ('Wekesa Barasa (Lavington)', ST_SetSRID(ST_MakePoint(36.77000, -1.28000), 4326));

-- Generate an additional 990 realistic riders distributed across greater Nairobi for benchmark scale
INSERT INTO riders (rider_name, location)
SELECT
    'Rider #' || i,
    ST_SetSRID(
        ST_MakePoint(
            36.70 + (random() * 0.20),  -- Nairobi longitude span ~ 36.70 to 36.90
            -1.35 + (random() * 0.15)  -- Nairobi latitude span ~ -1.35 to -1.20
        ),
        4326
    )
FROM generate_series(11, 1000) AS i;

