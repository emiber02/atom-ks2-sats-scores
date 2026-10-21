-- DDL for int_sitting_subject_results. Created once; never dropped by a normal run.
-- Partitioned on the time a result became available and clustered by pupil so that
-- point-in-time and per-pupil reads prune well once responses grow to 100m+ rows.
CREATE TABLE IF NOT EXISTS `{{project}}.{{dataset}}.int_sitting_subject_results` (
  session_id                         STRING    NOT NULL,
  subject_id                         STRING    NOT NULL,
  subject_name                       STRING,
  pupil_id                           STRING    NOT NULL,
  assessment_id                      STRING,
  session_type                       STRING,
  style                              STRING,
  year_group_at_sitting              INT64,
  total_questions                    INT64,
  is_complete                        BOOL,
  is_deleted                         BOOL,
  started_at                         TIMESTAMP,
  finished_at                        TIMESTAMP,
  available_at                       TIMESTAMP OPTIONS (description = 'When this result could first have been known: GREATEST(finished_at, last answer timestamp). Drives point-in-time logic.'),
  questions_answered                 INT64,
  questions_correct                  INT64,
  questions_no_attempt               INT64,
  questions_with_conflicting_dupes   INT64,
  raw_response_rows                  INT64,
  percent_correct                    FLOAT64,
  is_scoreable                       BOOL      OPTIONS (description = 'TRUE when the sitting may contribute to a SATs score.'),
  exclusion_reason                   STRING    OPTIONS (description = 'Why the sitting is not scoreable; NULL when scoreable.')
)
PARTITION BY DATE(available_at)
CLUSTER BY pupil_id, subject_id
OPTIONS (description = 'One row per assessment sitting x subject with question-level results aggregated. Incrementally maintained.');
