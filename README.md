# Atom Learning – KS2 SATs score model

Produces a KS2 SATs-equivalent score (80–120) for every pupil in every SATs subject from
Atom assessment responses. It is built in BigQuery as layered, re-runnable, point-in-time SQL models.

**Materialised in:** `atom-analytics-candidates.emilija_bernotaite`
**Answer table:** `pupil_sats_scores` (current score)
**Point-in-time:** `tvf_pupil_sats_scores_as_of(TIMESTAMP)` (score at any moment)

```sql
-- Current scores
SELECT * FROM `atom-analytics-candidates.emilija_bernotaite.pupil_sats_scores`;

-- Scores as they stood on 1 March 2026
SELECT * FROM `atom-analytics-candidates.emilija_bernotaite.tvf_pupil_sats_scores_as_of`(TIMESTAMP '2026-03-01');
```

---

## 1. What I built

```
RAW (de_raw)            STAGING (views)            INTERMEDIATE (incremental)        MARTS
responses ────────────► stg_responses ──────┐
assessment_sittings ──► stg_assessment_sittings ─► int_sitting_subject_results ──┐
course_hierarchy ─────► stg_course_hierarchy ┘      (1 row / sitting × subject)   │
                                                                                 ▼
REFERENCE                                                          fct_pupil_sats_score_history
seeds/ks2_scaled_score_conversion.csv (GOV.UK 2025)                 (SCD2: valid_from / valid_to)
  └► ref_ks2_scaled_score_conversion                                             │
       └► ref_ks2_percent_to_scaled_score ───────────────────────────────────────┤
ref_sats_subjects (English, Maths) ──────────────────────────────────────────────┤
                                                                                 ▼
pupils ───────────────► stg_pupils ─────────────────────────────► tvf_pupil_sats_scores_as_of(as_of)
                                                                                 │  evaluated at end of time
                                                                                 ▼
                                                                   pupil_sats_scores (current, app-facing)
```

| Layer | Model | Grain | Materialisation | Purpose |
|---|---|---|---|---|
| staging | `stg_responses` | session × question | view | De-duplicates answers and normalises flags. |
| staging | `stg_assessment_sittings` | session | view | Normalises casing and adds a year-group validity flag. |
| staging | `stg_course_hierarchy` | question | view | Question → subject hierarchy. |
| staging | `stg_pupils` | pupil | view | Pupil list with deleted flag. |
| reference | `ref_ks2_scaled_score_conversion` | test × raw mark | table (seed) | Official 2025 GOV.UK raw→scaled tables, loaded verbatim. |
| reference | `ref_sats_subjects` | Atom subject | table | Which Atom subjects have a SATs equivalent, and which KS2 tests they map to. |
| reference | `ref_ks2_percent_to_scaled_score` | SATs subject × 0.1% | table | Percent correct → scaled-score curve. |
| intermediate | `int_sitting_subject_results` | sitting × subject | partitioned, clustered table, incremental | Aggregated results per sitting plus a scoreable flag and exclusion reason. |
| mart | `fct_pupil_sats_score_history` | pupil × subject × version | partitioned, clustered table | Slowly changing (type 2) history of every score. |
| mart | `tvf_pupil_sats_scores_as_of(as_of)` | pupil × subject | table function | Point-in-time scores for any timestamp. |
| mart | `pupil_sats_scores` | pupil × subject | table with declared primary key | Current scores, shaped for the production database. |

### How a score is calculated

1. **Eligible evidence.** Only complete, non-deleted, `summative_assessment` sittings with
   `fixed_question` style count. Excluded sittings stay in `int_sitting_subject_results` with an
   `exclusion_reason`, so nothing is silently dropped.
2. **Pooling.** For each pupil and subject, pool the questions from the pupil's **latest 3
   scoreable sittings**. This is recent enough to show progress and broad enough not to swing on
   one bad day or one short quiz. Sittings range from 8 to 50 questions.
3. **Percent → raw mark.** Express the pooled percent correct as the equivalent raw mark on the
   real 2025 KS2 paper. For example, 60% in Maths is 66 of 110 marks.
4. **Raw mark → scaled score.** Look up the official GOV.UK 2025 conversion table and
   linearly interpolate between adjacent marks. Round to an integer, as real SATs are.
5. **English.** KS2 English is two papers: Reading out of 50 and Grammar, Punctuation & Spelling
   out of 70. Atom's English subject covers both, and the hierarchy exposes no topic names to
   separate them. The English curve is therefore the average of the two official curves.
6. **Minimum evidence.** Fewer than 10 pooled questions gives `score_status = 'insufficient_evidence'`
   and no score. A pupil with no scoreable sittings gets `no_evidence`. Every pupil still has a row
   for every SATs subject.
7. Flags `meets_expected_standard` (score of 100 or more) and `working_at_higher_standard`
   (110 or more) follow GOV.UK's definitions.

Resulting curve anchors, checked against the published expected-standard thresholds:

| % correct | English | Maths |
|---|---|---|
| 25% | 90 | 92 |
| 50% | 99 | 99 |
| 53% | 100 | 100 |
| 70% | 106 | 104 |
| 90% | 117 | 112 |

The pass marks for 100 match the published 2025 thresholds: Reading 28/50, GPS 35/70 and Maths 58/110.

### Current output

| Subject | Scored pupils | No evidence | Median | Meeting expected (100+) | Higher standard (110+) |
|---|---|---|---|---|---|
| English | 153 | 89 | 101 | 96 | 16 |
| Maths | 151 | 91 | 100 | 83 | 10 |

Nationally in 2025, about three quarters of pupils met the expected standard in each test.
Our cohort lands somewhat lower, which is plausible for a mixed Year 1–6 population assessed mid-year.

---

## 2. Design decisions for robustness

**Re-runnable.** Every model is either `CREATE OR REPLACE` from deterministic SQL or an idempotent
delete-and-insert of affected sessions inside a transaction. There is no `CURRENT_TIMESTAMP` in any
data column, and every tie-break is explicit. `scripts/build.sh --check-idempotency` builds twice and
compares an order-independent fingerprint of every table. It passes. An incremental run with
`INCREMENTAL_SINCE=2026-06-01` reproduces the full-build fingerprint exactly.

**Point-in-time.** Each sitting has an `available_at`, the later of `finished_at` and its last answer.
The score history is a type 2 table with `valid_from` and `valid_to`. A new version starts whenever a
scoreable sitting becomes available. `tvf_pupil_sats_scores_as_of(T)` returns the version valid at T.
`pupil_sats_scores` is that same function evaluated at the end of time, so "current" and "as of" cannot drift.

**Scales to 100m+ responses.**
- `int_sitting_subject_results` collapses roughly 25–50 response rows into one row per sitting.
  Everything downstream reads this table, never `responses`.
- It is loaded incrementally. Sessions with an answer since `INCREMENTAL_SINCE` are recomputed whole,
  which absorbs late-arriving answers.
- It is partitioned by `DATE(available_at)` and clustered by `pupil_id, subject_id`.
  The history is partitioned by month of `valid_from` and clustered by `pupil_id, sats_subject`.
- In production I would also ask for `de_raw.responses` to be partitioned on `answered_at`.
  Without that, the incremental filter still scans the whole raw table.

**Ready for the production database.** `pupil_sats_scores` is narrow and flat with no arrays.
It is explicitly typed, uses `NOT NULL` where a value always exists, and declares
`PRIMARY KEY (pupil_id, sats_subject)`. `score_status` is an enum-like column, and
`scoring_model_version` lets the app know which rules produced a value. Arrays such as
`contributing_session_ids` stay in the warehouse history table for explainability.

**Extensible.** Scoring parameters are build variables: `ROLLING_SITTINGS`, `MIN_QUESTIONS`,
`CONVERSION_YEAR` and `MODEL_VERSION`. A new year's GOV.UK table is a new seed load. A new SATs-like
subject is one row in `ref_sats_subjects`. Staging and the sitting layer contain no SATs-specific
logic, so a colleague answering a different question can start from `int_sitting_subject_results`.

**Tested.** `sql/05_tests/assert_models.sql` holds twelve `ASSERT` checks that run as the last build step.
They cover unique keys at every grain and reconciliation of responses from staging to the sitting
layer. They check one current history row per pupil and subject, with no empty intervals. They check
scores lie within 80–120 and agree with their status, and that every pupil has one row per subject.
They check the curve is monotonic and that no scores exist before any data.

---

## 3. Assumptions

1. **Assessments are calibrated to the pupil's year group.** A Year 3 pupil scoring 53% on a Year 3
   assessment is treated as "on track for 100". The score reads as "KS2-equivalent if this performance
   continues", not as a literal Year 6 prediction. The data supports this. Average percent correct is
   roughly flat across Years 1–6, at 52–66%, which is what you expect if each test is pitched at its year.
2. **Only English and Maths get SATs scores.** These are the only subjects with a KS2 scaled score.
   Science is teacher-assessed. Verbal and Non-Verbal Reasoning are 11+ subjects. Screeners and
   Wellbeing are not attainment measures. I read "every subject" as every SATs subject.
3. **Percent correct maps proportionally to raw marks on the real paper.** This ignores differences in
   difficulty between Atom questions and SATs questions.
4. **The latest 3 sittings** is a judgement call, balancing responsiveness against noise. It is a parameter.
5. **Unanswered or "no attempt" questions count as incorrect.** The pupil saw the question.
6. **Raw marks 0–2 have no scaled score on GOV.UK.** We floor them at 80 so every scored pupil sits on the scale.
7. **The 2025 conversion table** is the most recent with a full published table.
   The 2026 thresholds were reported in the press, but the build supports swapping tables.

## 4. Data quality findings

Evidence for each point is in `sql/analysis/data_quality_profile.sql`.

| # | Issue | Size | Handling |
|---|---|---|---|
| 1 | The same question appears 2–5 times within one sitting, with identical `answered_at` and `seconds_taken`. | 2,082 pairs, 4,493 rows | Collapsed to one answer per sitting and question. |
| 2 | Those duplicates **disagree on `is_correct`**, and there is no ordering signal to pick the "real" one. | 965 pairs | Conservative: correct only if every duplicate says correct. Flagged per sitting. |
| 3 | `responses.session_type` is always `MOCK_TEST`. The sittings table says `summative_assessment` for the same sessions. | all rows | Ignored. The sitting is the source of truth. |
| 4 | Responses whose `session_id` has no sitting record. | 1,433 rows, 56 sessions, 44 pupils | Excluded as `no_sitting_record`. Completeness and type can't be verified. |
| 5 | Answers timestamped after the sitting's `finished_at`. Mostly seconds late, one about 196 days late. | 1,608 rows, 236 sittings | `available_at` uses the later timestamp, so point-in-time never shows a result before it could exist. |
| 6 | Incomplete sittings, or sittings with no `finished_at`. | 13 sittings | Excluded. |
| 7 | Complete sittings with fewer distinct answered questions than `total_questions`. | 49 sittings | Scored on the answers present. Treating the gaps as wrong is the alternative. |
| 8 | `year_group_at_sitting` of 14 and 15 do not exist in England. Year 11 also appears. All are entrance exams. | 25 sittings | Flagged as invalid. These sittings have no responses anyway. |
| 9 | Pupils recorded in two different year groups within one academic year, such as Year 1 and Year 3. | 6 pupils | Kept. `latest_year_group` is exposed. Worth raising with the product team. |
| 10 | Sittings with no responses at all, including every `entrance_exam` and `mock_session`. | 79 sittings | No effect on scoring. |
| 11 | Pupils with no responses at all. | 78 of 242 | They receive `no_evidence` rows. |
| 12 | The hierarchy has IDs only, with no topic names. English Reading and GPS can't be separated. | n/a | English uses the averaged curve. See assumption 2 and item 5 of how a score is calculated. |
| 13 | No `created_at`, `updated_at` or ingestion timestamps on any raw table. | n/a | Point-in-time works on event time, not ingestion time. Changes to sittings, such as deletions, can't be detected incrementally. Run a full refresh, or add change data capture. |

## 5. How to run

Requirements: the Google Cloud SDK (`bq`), authenticated with access to `atom-analytics-candidates`.

```bash
scripts/build.sh                                  # full build into emilija_bernotaite
DATASET=my_dev scripts/build.sh                   # build elsewhere
INCREMENTAL_SINCE=2026-09-01 scripts/build.sh     # incremental refresh of the sitting layer
scripts/build.sh --check-idempotency              # build twice and compare fingerprints
python scripts/fetch_ks2_conversion_tables.py > seeds/ks2_scaled_score_conversion.csv   # refresh the seed from GOV.UK
```

SQL files use `{{placeholders}}` such as `{{project}}`, `{{dataset}}` and `{{min_questions}}`.
`build.sh` renders them and runs the files in dependency order. The structure maps one-to-one onto
dbt models if Atom uses dbt: staging views, a seed, an incremental model and marts.

```
sql/01_staging/        stg_* views
sql/02_reference/      SATs subject mapping and percent → scaled curve
sql/03_intermediate/   int_sitting_subject_results (DDL + incremental load)
sql/04_marts/          score history, as-of table function, current app table
sql/05_tests/          ASSERT data tests, run at the end of every build
sql/analysis/          data-quality profiling queries
seeds/                 official GOV.UK 2025 KS2 conversion tables
scripts/               build runner, seed fetcher
docs/ai/               AI planning notes and prompt log
```

## 6. What I would do next

1. **Calibrate per assessment instead of assuming every test is pitched at its year.** Fit an item
   response model, or simple equipercentile linking, from Atom scores to real KS2 outcomes for pupils
   where we know both. That gives per-assessment and per-year-group conversions.
2. **Weight English by component** once topic names let us split Reading from GPS.
3. **Add uncertainty.** Expose a confidence band from the number of questions pooled, so teachers can
   see that a score from 12 questions is less certain than one from 120.
4. **Resolve the duplicate-answer issue at source** with the engineering team. Conflicting correctness
   on identical timestamps looks like a client retry or event-logging bug.
5. **Add ingestion timestamps or change data capture** to the raw tables, enabling true bitemporal
   point-in-time ("what did the dashboard show on date X") and incremental handling of sitting updates.
6. **Move to dbt** with schema tests and freshness checks, and orchestrate daily incremental runs.

---

## 7. Step 3 (optional): predicting GCSE results from primary-school work

**What to predict, and from what.** The target is GCSE grades (9–1) in English Language and Maths
at age 16. The core features are a pupil's KS2-equivalent trajectory from this model: level, slope
across Years 1–6, and consistency. Item-level strengths add to that, such as fractions versus
geometry and inference versus retrieval. Engagement adds more: volume, recency and time per question.
The predictive signal is mostly in **attainment and trajectory**, so the SATs model above is the
natural feature layer.

**Data we would need.** The hard part is the label. Atom sees pupils at primary school, so we would
need linked outcomes years later. One route is the National Pupil Database, which links KS2 results
to KS4 results by pupil (via a DfE data-sharing application). The other is partner schools sharing
anonymised GCSE results. Without that, a practical proxy is a two-stage model. Stage one predicts
actual KS2 scaled scores from Atom data, which needs schools to share real SATs results. Stage two
maps KS2 to GCSE using the published national KS2→KS4 transition matrices. The DfE publishes the
distribution of GCSE grades by KS2 prior attainment, the basis of Progress 8. We would also want
context features: disadvantage status (pupil premium or free school meals), English as an additional
language, special educational needs, school, and month of birth. These are known strong predictors
of progress between Key Stages.

**Assumptions and caveats.** Five years of secondary schooling sit between the evidence and the
outcome, so the prediction is probabilistic. It should show a distribution of grades, not a single
grade. Relationships learned from past cohorts must hold for future ones, despite curriculum and
grade-boundary changes and post-COVID effects. Atom users are not a random sample of pupils, so
selection bias needs checking against national distributions. Contextual features carry fairness
risk. Used naively, they can encode lower expectations for disadvantaged pupils, so the product
should show predictions as "what is likely without intervention", never as a ceiling. A simple,
explainable starting point is a regression of GCSE grade on KS2 score plus a few context features,
evaluated on held-out cohorts. That is the baseline any more complex model must beat.

---

## 8. Use of AI

Built with **Claude Code**, Anthropic's command-line coding agent, in a single session. Claude ran
the profiling queries through the `bq` CLI, parsed the GOV.UK conversion tables, drafted the SQL and
docs, and ran the build, tests and idempotency check against BigQuery. All design decisions are
recorded in `docs/ai/planning.md`, and the prompt and workflow in `docs/ai/prompts.md`. Commits are
co-authored to show which work was AI-assisted.
