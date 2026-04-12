-- OMOP SOFA v4.4 - Create schemas
-- Creates results schema for output tables

CREATE SCHEMA IF NOT EXISTS results;

GRANT USAGE ON SCHEMA results TO PUBLIC;
GRANT CREATE ON SCHEMA results TO PUBLIC;

COMMENT ON SCHEMA results IS 'OMOP SOFA v4.4 output tables - all 10 flaws fixed';

SELECT 'Schema results created successfully' AS status;
