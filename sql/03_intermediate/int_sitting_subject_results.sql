-- int_sitting_subject_results
-- Grain: one row per (session_id, subject_id).
--
-- This is the layer that keeps the pipeline cheap at production volume: it collapses
-- ~25-50 response rows into one row per sitting, and everything downstream reads from here.
--
-- Load pattern: idempotent "replace the affected sessions" inside a transaction.
--   * {{incremental_since}} = '1970-01-01' rebuilds everything (default, used for this submission).
--   * In production set it to e.g. last successful run - 3 days. Any session with an answer
--     at or after that point is recomputed in full, so late-arriving answers are absorbed.
-- Running the script twice with the same input yields the same table (no CURRENT_TIMESTAMP,
-- no non-deterministic picks).
DECLARE since TIMESTAMP DEFAULT TIMESTAMP('{{incremental_since}}');

CREATE TEMP TABLE touched_sessions AS
SELECT DISTINCT session_id
FROM `{{project}}.{{dataset}}.stg_responses`
WHERE last_answered_at >= since;

CREATE TEMP TABLE new_rows AS
WITH responses AS (
  SELECT r.*
  FROM `{{project}}.{{dataset}}.stg_responses` AS r
  JOIN touched_sessions USING (session_id)
),

aggregated AS (
  SELECT
    r.session_id,
    h.subject_id,
    ANY_VALUE(h.subject_name)               AS subject_name,
    MIN(r.pupil_id)                         AS response_pupil_id,
    COUNT(*)                                AS questions_answered,
    COUNTIF(r.is_correct)                   AS questions_correct,
    COUNTIF(r.is_no_attempt)                AS questions_no_attempt,
    COUNTIF(r.has_conflicting_duplicates)   AS questions_with_conflicting_dupes,
    SUM(r.raw_row_count)                    AS raw_response_rows,
    MAX(r.last_answered_at)                 AS last_answered_at
  FROM responses AS r
  JOIN `{{project}}.{{dataset}}.stg_course_hierarchy` AS h USING (question_id)
  GROUP BY r.session_id, h.subject_id
)

SELECT
  a.session_id,
  a.subject_id,
  a.subject_name,
  COALESCE(s.pupil_id, a.response_pupil_id)          AS pupil_id,
  s.assessment_id,
  s.session_type,
  s.style,
  s.year_group_at_sitting,
  s.total_questions,
  s.is_complete,
  s.is_deleted,
  s.started_at,
  s.finished_at,
  GREATEST(s.finished_at, a.last_answered_at)        AS available_at,
  a.questions_answered,
  a.questions_correct,
  a.questions_no_attempt,
  a.questions_with_conflicting_dupes,
  a.raw_response_rows,
  SAFE_DIVIDE(a.questions_correct, a.questions_answered) AS percent_correct,
  exclusion_reason IS NULL                           AS is_scoreable,
  exclusion_reason
FROM aggregated AS a
LEFT JOIN `{{project}}.{{dataset}}.stg_assessment_sittings` AS s USING (session_id)
CROSS JOIN UNNEST([
  -- First matching rule wins; order is most-fundamental first.
  CASE
    WHEN s.session_id IS NULL                        THEN 'no_sitting_record'
    WHEN s.is_deleted                                THEN 'sitting_deleted'
    WHEN NOT s.is_complete OR s.finished_at IS NULL  THEN 'sitting_incomplete'
    WHEN s.session_type != 'summative_assessment'    THEN 'not_summative_assessment'
    WHEN s.style != 'fixed_question'                 THEN 'not_fixed_question_style'
    WHEN NOT s.is_valid_year_group                   THEN 'invalid_year_group'
    WHEN s.pupil_id != a.response_pupil_id           THEN 'pupil_mismatch'
  END
]) AS exclusion_reason;

BEGIN TRANSACTION;

DELETE FROM `{{project}}.{{dataset}}.int_sitting_subject_results`
WHERE session_id IN (SELECT session_id FROM touched_sessions);

INSERT INTO `{{project}}.{{dataset}}.int_sitting_subject_results`
SELECT * FROM new_rows;

COMMIT TRANSACTION;
