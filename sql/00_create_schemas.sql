-- 00_create_schemas.sql
-- Create results schema used by all downstream objects
-- Run this FIRST with -v results_schema=... -v cdm_schema=...

CREATE SCHEMA IF NOT EXISTS :results_schema;
