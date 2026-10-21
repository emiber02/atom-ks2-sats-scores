-- Data quality profile of the raw tables. Read-only; run ad hoc, not part of the build.
-- Each query is the evidence behind one point in README "Data quality findings".
-- Replace `de_raw` if profiling a different raw dataset.

-- 1. responses: keys, nulls, ranges
SELECT
  COUNT(*)                          AS n_rows,
  COUNT(DISTINCT response_id)       AS n_distinct_response_id,
  COUNTIF(is_no_attempt)            AS n_no_attempt,
  COUNTIF(is_no_attempt AND is_correct) AS n_no_attempt_but_correct,
  MIN(answered_at)                  AS first_answer,
  MAX(answered_at)                  AS last_answer,
  MAX(seconds_taken)                AS max_seconds_taken
FROM de_raw.responses;

-- 2. responses: one session_type only, contradicting assessment_sittings
SELECT session_type, COUNT(*) FROM de_raw.responses GROUP BY 1;

-- 3. duplicate answers to the same question in the same sitting, and whether they disagree
WITH d AS (
  SELECT session_id, question_id,
         COUNT(*) AS n,
         COUNT(DISTINCT is_correct)  AS distinct_correct,
         COUNT(DISTINCT answered_at) AS distinct_ts
  FROM de_raw.responses
  GROUP BY 1, 2
  HAVING n > 1
)
SELECT
  COUNT(*)                     AS duplicated_pairs,
  SUM(n)                       AS rows_involved,
  COUNTIF(distinct_correct > 1) AS pairs_with_conflicting_correctness,
  COUNTIF(distinct_ts > 1)      AS pairs_with_different_timestamps
FROM d;

-- 4. referential integrity of responses
SELECT
  COUNTIF(s.session_id IS NULL)          AS responses_without_sitting,
  COUNT(DISTINCT IF(s.session_id IS NULL, r.session_id, NULL)) AS orphan_sessions,
  COUNTIF(s.pupil_id != r.pupil_id)      AS pupil_mismatch,
  COUNTIF(h.question_id IS NULL)         AS responses_without_hierarchy,
  COUNTIF(r.answered_at > s.finished_at) AS answered_after_sitting_finished
FROM de_raw.responses r
LEFT JOIN de_raw.assessment_sittings s USING (session_id)
LEFT JOIN de_raw.course_hierarchy h USING (question_id);

-- 5. sittings by type/style/status
SELECT session_type, style, is_complete, is_deleted,
       COUNT(*) AS sittings, COUNT(DISTINCT assessment_id) AS assessments,
       MIN(total_questions), MAX(total_questions)
FROM de_raw.assessment_sittings
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;

-- 6. year groups (14 and 15 do not exist in England)
SELECT year_group_at_sitting, session_type, COUNT(*) AS sittings
FROM de_raw.assessment_sittings
GROUP BY 1, 2
ORDER BY 1, 2;

-- 7. pupils recorded in more than one year group
SELECT pupil_id, ARRAY_AGG(DISTINCT year_group_at_sitting) AS year_groups,
       MIN(started_at), MAX(started_at)
FROM de_raw.assessment_sittings
GROUP BY 1
HAVING COUNT(DISTINCT year_group_at_sitting) > 1;

-- 8. answered questions vs total_questions after de-duplication
WITH d AS (SELECT session_id, COUNT(DISTINCT question_id) AS nq FROM de_raw.responses GROUP BY 1)
SELECT
  CASE WHEN nq = total_questions THEN 'equal' WHEN nq < total_questions THEN 'fewer' ELSE 'more' END AS answered_vs_total,
  is_complete,
  COUNT(*)
FROM d JOIN de_raw.assessment_sittings USING (session_id)
GROUP BY 1, 2;

-- 9. sittings with no responses at all; every sitting covers exactly one subject
SELECT COUNT(*) AS sittings_without_responses
FROM de_raw.assessment_sittings s
WHERE NOT EXISTS (SELECT 1 FROM de_raw.responses r WHERE r.session_id = s.session_id);

SELECT n_subjects, COUNT(*) AS sittings
FROM (
  SELECT session_id, COUNT(DISTINCT subject_id) AS n_subjects
  FROM de_raw.responses JOIN de_raw.course_hierarchy USING (question_id)
  GROUP BY 1
)
GROUP BY 1;

-- 10. average percent correct by subject and year group: roughly flat, which supports
--     treating each assessment as calibrated to its own year group
SELECT h.subject_name, s.year_group_at_sitting,
       COUNT(DISTINCT s.assessment_id) AS assessments,
       COUNT(*) AS sittings,
       ROUND(AVG(r.pct), 3) AS avg_percent_correct
FROM (SELECT session_id, AVG(CAST(is_correct AS INT64)) AS pct FROM de_raw.responses GROUP BY 1) r
JOIN de_raw.assessment_sittings s USING (session_id)
JOIN (SELECT DISTINCT session_id, subject_name FROM de_raw.responses JOIN de_raw.course_hierarchy USING (question_id)) h USING (session_id)
WHERE h.subject_name IN ('English', 'Maths')
GROUP BY 1, 2
ORDER BY 1, 2;
