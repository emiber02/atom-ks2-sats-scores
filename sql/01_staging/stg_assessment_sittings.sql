-- stg_assessment_sittings
-- Grain: one row per session_id (an assessment sat by a pupil).
-- Normalises types/casing and adds validity flags. Nothing is filtered out here:
-- the decision of which sittings count towards a SATs score lives downstream
-- (int_sitting_subject_results.is_scoreable) so other use-cases can reuse this model.
CREATE OR REPLACE VIEW `{{project}}.{{dataset}}.stg_assessment_sittings` AS
SELECT
  session_id,
  pupil_id,
  assessment_id,
  LOWER(session_type)                         AS session_type,
  LOWER(style)                                AS style,
  year_group_at_sitting,
  -- England has school Years R-13. Values 14/15 appear in the raw data (entrance exams only).
  year_group_at_sitting BETWEEN 0 AND 13      AS is_valid_year_group,
  total_questions,
  COALESCE(is_complete, FALSE)                AS is_complete,
  COALESCE(is_deleted, FALSE)                 AS is_deleted,
  started_at,
  finished_at
FROM `{{project}}.{{raw_dataset}}.assessment_sittings`
WHERE session_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY session_id
  ORDER BY finished_at DESC NULLS LAST, started_at DESC NULLS LAST, pupil_id
) = 1;
