-- pupil_sats_scores
-- Grain: one row per (pupil_id, sats_subject). Primary key (pupil_id, sats_subject).
--
-- The application-facing table: the latest score for every pupil in every SATs subject.
-- Shaped for migration into an OLTP database: narrow, explicitly typed, declared primary key,
-- no nested/array columns, NOT NULL where the value always exists, enum-like status column,
-- and a model version so the app can tell which scoring rules produced a value.
-- It is defined as the table function evaluated at the end of time, so "current" and
-- "point-in-time" can never drift apart.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.pupil_sats_scores` (
  pupil_id                    STRING    NOT NULL,
  sats_subject                STRING    NOT NULL OPTIONS (description = 'ENGLISH or MATHS'),
  sats_score                  INT64              OPTIONS (description = 'KS2-equivalent scaled score 80-120; NULL unless score_status is scored'),
  score_status                STRING    NOT NULL OPTIONS (description = 'scored, insufficient_evidence or no_evidence'),
  meets_expected_standard     BOOL               OPTIONS (description = 'sats_score >= 100'),
  working_at_higher_standard  BOOL               OPTIONS (description = 'sats_score >= 110'),
  percent_correct             FLOAT64            OPTIONS (description = 'Pooled percent correct across the sittings used'),
  questions_answered          INT64     NOT NULL,
  questions_correct           INT64     NOT NULL,
  sittings_used               INT64     NOT NULL,
  latest_year_group           INT64              OPTIONS (description = 'Year group at the most recent sitting used'),
  score_valid_from            TIMESTAMP          OPTIONS (description = 'When this score came into effect'),
  score_history_id            STRING             OPTIONS (description = 'FK to fct_pupil_sats_score_history'),
  conversion_source_year      INT64              OPTIONS (description = 'Year of the GOV.UK conversion table used'),
  scoring_model_version       STRING    NOT NULL,
  PRIMARY KEY (pupil_id, sats_subject) NOT ENFORCED
)
CLUSTER BY pupil_id
OPTIONS (description = 'Current SATs score (80-120) per pupil per subject. App-facing.')
AS
SELECT *
FROM `{{project}}.{{dataset}}.tvf_pupil_sats_scores_as_of`(TIMESTAMP '9999-12-31 23:59:59.999999 UTC');
