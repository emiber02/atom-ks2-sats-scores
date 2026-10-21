-- stg_responses
-- Grain: one row per (session_id, question_id), i.e. one answer per question per sitting.
--
-- Data quality handled here (see README "Data quality"):
--   * ~2k (session, question) pairs appear 2-5 times with IDENTICAL answered_at and
--     seconds_taken but sometimes DIFFERENT is_correct. There is no ordering signal to pick
--     a "last" answer, so we collapse them deterministically and conservatively:
--     a question counts as correct only if every duplicate row says correct.
--   * is_no_attempt is treated as incorrect (the pupil was shown the question).
--   * responses.session_type is always 'MOCK_TEST' and contradicts the sittings table,
--     so it is deliberately not carried forward; the sitting is the source of truth.
CREATE OR REPLACE VIEW `{{project}}.{{dataset}}.stg_responses` AS
SELECT
  session_id,
  question_id,
  MIN(pupil_id)                                          AS pupil_id,
  MIN(response_id)                                       AS response_id,       -- deterministic representative
  MIN(question_number)                                   AS question_number,
  LOGICAL_AND(COALESCE(is_correct, FALSE)
              AND NOT COALESCE(is_no_attempt, FALSE))    AS is_correct,
  LOGICAL_AND(COALESCE(is_no_attempt, FALSE))            AS is_no_attempt,
  MAX(seconds_taken)                                     AS seconds_taken,
  MIN(answered_at)                                       AS answered_at,
  MAX(answered_at)                                       AS last_answered_at,
  COUNT(*)                                               AS raw_row_count,
  COUNT(DISTINCT is_correct) > 1                         AS has_conflicting_duplicates
FROM `{{project}}.{{raw_dataset}}.responses`
WHERE session_id IS NOT NULL
  AND question_id IS NOT NULL
GROUP BY session_id, question_id;
