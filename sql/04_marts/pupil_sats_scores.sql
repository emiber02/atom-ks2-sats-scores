-- pupil_sats_scores
-- Grain: one row per (pupil_id, sats_subject). Primary key (pupil_id, sats_subject).
--
-- The application-facing table: the latest score for every pupil in every Atom subject.
-- mapping_type tells the app whether to label a score as a SATs score (official), a
-- SATs-style estimate (proxy), or not to show a score at all (not_attainment).
-- Shaped for migration into an OLTP database: narrow, explicitly typed, declared primary key,
-- no nested/array columns, NOT NULL where the value always exists, enum-like status column,
-- and a model version so the app can tell which scoring rules produced a value.
-- It is defined as the table function evaluated at the end of time, so "current" and
-- "point-in-time" can never drift apart.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.pupil_sats_scores` (
  pupil_id                    STRING    NOT NULL,
  sats_subject                STRING    NOT NULL OPTIONS (description = 'Atom subject code: ENGLISH, MATHS, SCIENCE, VERBAL_REASONING, NON_VERBAL_REASONING, SCREENERS, WELLBEING'),
  mapping_type                STRING    NOT NULL OPTIONS (description = 'official (published KS2 curve), proxy (SATs-style estimate on a generic KS2 curve) or not_attainment (never scored)'),
  sats_score                  INT64              OPTIONS (description = 'KS2-equivalent scaled score 80-120; NULL unless score_status is scored. Official only when mapping_type is official'),
  score_status                STRING    NOT NULL OPTIONS (description = 'scored, insufficient_evidence, no_evidence or not_attainment'),
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
