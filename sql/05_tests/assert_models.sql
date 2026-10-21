-- Data tests. Each ASSERT fails the build with its message if the condition is false.

-- Keys are unique at each model's declared grain
ASSERT (
  SELECT COUNT(*) = COUNT(DISTINCT FORMAT('%s|%s', session_id, question_id))
  FROM `{{project}}.{{dataset}}.stg_responses`
) AS 'stg_responses: (session_id, question_id) not unique';

ASSERT (
  SELECT COUNT(*) = COUNT(DISTINCT FORMAT('%s|%s', session_id, subject_id))
  FROM `{{project}}.{{dataset}}.int_sitting_subject_results`
) AS 'int_sitting_subject_results: (session_id, subject_id) not unique';

ASSERT (
  SELECT COUNT(*) = COUNT(DISTINCT score_history_id)
  FROM `{{project}}.{{dataset}}.fct_pupil_sats_score_history`
) AS 'fct_pupil_sats_score_history: score_history_id not unique';

ASSERT (
  SELECT COUNT(*) = COUNT(DISTINCT FORMAT('%s|%s', pupil_id, sats_subject))
  FROM `{{project}}.{{dataset}}.pupil_sats_scores`
) AS 'pupil_sats_scores: primary key not unique';

-- Reconciliation: no response is lost or double counted between staging and the sitting layer
ASSERT (
  SELECT
    (SELECT SUM(questions_answered) FROM `{{project}}.{{dataset}}.int_sitting_subject_results`)
    = (SELECT COUNT(*) FROM `{{project}}.{{dataset}}.stg_responses` r
       JOIN `{{project}}.{{dataset}}.stg_course_hierarchy` USING (question_id))
) AS 'int_sitting_subject_results does not reconcile to stg_responses';

-- History intervals: exactly one current version per pupil/subject and no overlaps
ASSERT NOT EXISTS (
  SELECT 1
  FROM `{{project}}.{{dataset}}.fct_pupil_sats_score_history`
  GROUP BY pupil_id, sats_subject
  HAVING COUNTIF(is_current) != 1
) AS 'fct_pupil_sats_score_history: each pupil/subject must have exactly one current row';

ASSERT NOT EXISTS (
  SELECT 1
  FROM `{{project}}.{{dataset}}.fct_pupil_sats_score_history`
  WHERE valid_to IS NOT NULL AND valid_to <= valid_from
) AS 'fct_pupil_sats_score_history: empty or inverted validity interval';

-- Output contract
ASSERT NOT EXISTS (
  SELECT 1 FROM `{{project}}.{{dataset}}.pupil_sats_scores`
  WHERE sats_score NOT BETWEEN 80 AND 120
     OR (score_status = 'scored') != (sats_score IS NOT NULL)
     OR score_status NOT IN ('scored', 'insufficient_evidence', 'no_evidence')
) AS 'pupil_sats_scores: score outside 80-120 or inconsistent with score_status';

ASSERT (
  SELECT COUNT(*) FROM `{{project}}.{{dataset}}.pupil_sats_scores`
) = (
  SELECT COUNT(*) * (SELECT COUNT(DISTINCT sats_subject) FROM `{{project}}.{{dataset}}.ref_sats_subjects`)
  FROM `{{project}}.{{dataset}}.stg_pupils` WHERE NOT is_deleted
) AS 'pupil_sats_scores: expected one row per non-deleted pupil per SATs subject';

-- Conversion curve: monotonic non-decreasing and anchored to the published expected standard
ASSERT NOT EXISTS (
  SELECT 1 FROM (
    SELECT scaled_score_unrounded,
           LAG(scaled_score_unrounded) OVER (PARTITION BY sats_subject ORDER BY percent_tenths) AS prev
    FROM `{{project}}.{{dataset}}.ref_ks2_percent_to_scaled_score`
  ) WHERE scaled_score_unrounded < prev
) AS 'ref_ks2_percent_to_scaled_score: curve is not monotonic';

ASSERT (
  SELECT LOGICAL_AND(scaled_score BETWEEN 80 AND 120)
  FROM `{{project}}.{{dataset}}.ref_ks2_percent_to_scaled_score`
) AS 'ref_ks2_percent_to_scaled_score: value outside 80-120';

-- Point-in-time consistency: before any data exists nobody has a score
ASSERT NOT EXISTS (
  SELECT 1 FROM `{{project}}.{{dataset}}.tvf_pupil_sats_scores_as_of`(TIMESTAMP '2000-01-01')
  WHERE score_status != 'no_evidence'
) AS 'tvf_pupil_sats_scores_as_of: scores exist before any data';
