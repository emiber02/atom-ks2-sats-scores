-- tvf_pupil_sats_scores_as_of(as_of)
-- Grain: one row per (non-deleted pupil, sats_subject), as the score stood at `as_of`.
--
-- Every pupil gets a row for every SATs subject. Pupils with no scoreable evidence yet get
-- sats_score = NULL and score_status = 'no_evidence', so the application never has to infer
-- "missing" from an absent row.
--
-- Example:
--   SELECT * FROM `{{project}}.{{dataset}}.tvf_pupil_sats_scores_as_of`(TIMESTAMP '2026-03-01');
--
-- Limitation: pupils has no created_at, so a pupil appears for all as_of dates; and raw tables
-- have no ingestion timestamps, so this is point-in-time on event time (when the sitting
-- finished), not on when the data reached the warehouse.
CREATE OR REPLACE TABLE FUNCTION `{{project}}.{{dataset}}.tvf_pupil_sats_scores_as_of`(as_of TIMESTAMP) AS
SELECT
  p.pupil_id,
  s.sats_subject,
  h.sats_score,
  COALESCE(h.score_status, 'no_evidence')  AS score_status,
  h.meets_expected_standard,
  h.working_at_higher_standard,
  h.percent_correct,
  COALESCE(h.questions_answered, 0)        AS questions_answered,
  COALESCE(h.questions_correct, 0)         AS questions_correct,
  COALESCE(h.sittings_used, 0)             AS sittings_used,
  h.latest_year_group,
  h.valid_from                             AS score_valid_from,
  h.score_history_id,
  h.conversion_source_year,
  '{{model_version}}'                      AS scoring_model_version
FROM `{{project}}.{{dataset}}.stg_pupils` AS p
CROSS JOIN (SELECT DISTINCT sats_subject FROM `{{project}}.{{dataset}}.ref_sats_subjects`) AS s
LEFT JOIN `{{project}}.{{dataset}}.fct_pupil_sats_score_history` AS h
  ON  h.pupil_id = p.pupil_id
  AND h.sats_subject = s.sats_subject
  AND h.valid_from <= as_of
  AND (h.valid_to > as_of OR h.valid_to IS NULL)
WHERE NOT p.is_deleted;
