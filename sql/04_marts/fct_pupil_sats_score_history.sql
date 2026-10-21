-- fct_pupil_sats_score_history
-- Grain: one row per (pupil_id, sats_subject, valid_from). A slowly-changing (type 2) history
--        of every pupil's SATs score: a new version starts each time a scoreable sitting
--        becomes available.
--
-- Scoring rule (deliberately simple, see README):
--   * Pool the questions from the pupil's latest {{rolling_sittings}} scoreable sittings in the subject
--     (recent enough to track progress, wide enough not to swing on one bad day).
--   * percent correct -> KS2 scaled score via ref_ks2_percent_to_scaled_score.
--   * Fewer than {{min_questions}} pooled questions -> no score (status 'insufficient_evidence').
--
-- Point-in-time: the score as it stood at time T is the row where
--   valid_from <= T AND (valid_to > T OR valid_to IS NULL).
-- Use tvf_pupil_sats_scores_as_of(T) rather than writing that predicate by hand.
--
-- Full rebuild from int_sitting_subject_results (which is ~1/30th the size of responses).
-- If this ever becomes too large to rebuild, the same logic can be applied per pupil for
-- only the pupils touched by the latest increment.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.fct_pupil_sats_score_history`
PARTITION BY TIMESTAMP_TRUNC(valid_from, MONTH)
CLUSTER BY pupil_id, sats_subject
OPTIONS (description = 'SCD2 history of pupil SATs scores (80-120). Query with tvf_pupil_sats_scores_as_of.')
AS
WITH scoreable_sittings AS (
  SELECT
    r.pupil_id,
    s.sats_subject,
    r.session_id,
    r.available_at,
    r.year_group_at_sitting,
    r.questions_answered,
    r.questions_correct
  FROM `{{project}}.{{dataset}}.int_sitting_subject_results` AS r
  JOIN `{{project}}.{{dataset}}.ref_sats_subjects` AS s USING (subject_id)
  WHERE r.is_scoreable
),

rolling AS (
  SELECT
    pupil_id,
    sats_subject,
    available_at,
    session_id                      AS triggering_session_id,
    year_group_at_sitting           AS latest_year_group,
    SUM(questions_answered)  OVER w AS questions_answered,
    SUM(questions_correct)   OVER w AS questions_correct,
    COUNT(*)                 OVER w AS sittings_used,
    ARRAY_AGG(session_id)    OVER w AS contributing_session_ids
  FROM scoreable_sittings
  -- If two sittings become available at the same instant, keep one version (the one whose
  -- window already includes both) so validity intervals never have zero length.
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY pupil_id, sats_subject, available_at ORDER BY session_id DESC
  ) = 1
  WINDOW w AS (
    PARTITION BY pupil_id, sats_subject
    ORDER BY available_at, session_id
    ROWS BETWEEN {{rolling_sittings_preceding}} PRECEDING AND CURRENT ROW
  )
),

versioned AS (
  SELECT
    *,
    available_at AS valid_from,
    LEAD(available_at) OVER (PARTITION BY pupil_id, sats_subject ORDER BY available_at) AS valid_to,
    CAST(ROUND(1000 * SAFE_DIVIDE(questions_correct, questions_answered)) AS INT64) AS percent_tenths
  FROM rolling
)

SELECT
  TO_HEX(MD5(CONCAT(v.pupil_id, '|', v.sats_subject, '|', FORMAT_TIMESTAMP('%FT%H:%M:%E6S', v.valid_from))))
                                                  AS score_history_id,
  v.pupil_id,
  v.sats_subject,
  v.valid_from,
  v.valid_to,
  v.valid_to IS NULL                              AS is_current,
  IF(v.questions_answered >= {{min_questions}}, c.scaled_score, NULL)           AS sats_score,
  IF(v.questions_answered >= {{min_questions}}, c.scaled_score_unrounded, NULL) AS sats_score_unrounded,
  IF(v.questions_answered >= {{min_questions}}, 'scored', 'insufficient_evidence') AS score_status,
  IF(v.questions_answered >= {{min_questions}}, c.scaled_score >= 100, NULL)    AS meets_expected_standard,
  IF(v.questions_answered >= {{min_questions}}, c.scaled_score >= 110, NULL)    AS working_at_higher_standard,
  v.percent_tenths / 10                           AS percent_correct,
  v.questions_answered,
  v.questions_correct,
  v.sittings_used,
  v.contributing_session_ids,
  v.triggering_session_id,
  v.latest_year_group,
  c.conversion_source_year,
  '{{model_version}}'                             AS scoring_model_version
FROM versioned AS v
JOIN `{{project}}.{{dataset}}.ref_ks2_percent_to_scaled_score` AS c
  ON c.sats_subject = v.sats_subject
 AND c.percent_tenths = v.percent_tenths;
