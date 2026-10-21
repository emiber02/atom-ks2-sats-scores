-- stg_pupils
-- Grain: one row per pupil_id.
-- Light-touch cleaning of the raw pupils table. Defensive de-duplication on the key
-- (none found in the current extract, but the raw table enforces nothing).
CREATE OR REPLACE VIEW `{{project}}.{{dataset}}.stg_pupils` AS
SELECT
  pupil_id,
  COALESCE(is_deleted, FALSE) AS is_deleted
FROM `{{project}}.{{raw_dataset}}.pupils`
WHERE pupil_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY pupil_id ORDER BY is_deleted DESC) = 1;
