# AI planning and decision log

Working notes from the Claude Code session that built this project, kept in the order the
decisions were made. They show the reasoning, including options that were rejected.

## 0. Framing the brief

- The deliverable is a score per pupil per subject on 80–120, plus models that are re-runnable,
  point-in-time, scalable, and shaped for an app database.
- The brief is deliberately PM-style and ambiguous. Plan: profile first, then decide.
  Every judgement call gets written down.
- Tooling: the `bq` CLI was authenticated. The default gcloud project lacked `jobs.create`,
  so every query bills to `atom-analytics-candidates`. Build target: `emilija_bernotaite`.

## 1. Profiling: what the data actually says

The queries are in `sql/analysis/data_quality_profile.sql`.

| Observation | Consequence for design |
|---|---|
| Responses: 63.7k rows, `response_id` unique, but (session, question) duplicated 2–5× with identical timestamps | De-duplicate in staging. Timestamps can't break ties. |
| 965 of the duplicate pairs disagree on `is_correct` | Need a deterministic, defensible rule. Chose conservative `LOGICAL_AND`. Majority vote fails on 2-row ties. "Any correct" would reward double-submits. |
| After de-duplication, answered questions equal `total_questions` for 2,379 of 2,430 sittings | Confirms duplicates, not extra questions, caused the over-counts. |
| `responses.session_type` is always MOCK_TEST, while sittings say summative | Trust sittings. Drop the column. |
| Sittings: summative fixed_question (2,342), survey (125, Wellbeing), entrance_exam and mock_session (no responses) | Eligibility rule: complete, not deleted, summative, fixed_question. |
| Every sitting covers exactly one subject | Grain sitting × subject still chosen, to be safe for future mixed tests. |
| Subjects: English, Maths, Science, VR, NVR, Screeners, Wellbeing | Only English and Maths have KS2 scaled scores. The others are out of scope, by reasoned choice. |
| Year groups 1–6, plus 11, 14 and 15 on entrance exams | Add a validity flag. These sittings have no responses. |
| Average percent correct is flat, 52–66%, across Years 1–6 | Evidence that assessments are pitched at year group. Supports a single percent→scaled curve. |
| 56 orphan sessions; answers after `finished_at` (one ~196 days late) | Exclude orphans. Use `available_at = GREATEST(finished_at, last answer)` for point-in-time. |
| No ingestion or updated timestamps anywhere | Point-in-time on event time only. Documented as a limitation. |

## 2. Conversion to the 80–120 scale

Options considered:

1. **Linear map**, 0% to 80 and 100% to 120. Simple but wrong: real SATs are non-linear and 100 sits near 53%, not 50%.
2. **Official GOV.UK raw→scaled tables via percent of max raw.** **Chosen.** Grounded in published
   data, captures the non-linearity, and is easy to explain to a teacher.
3. **Norm-referencing**, matching our pupils' percentile distribution to the national score
   distribution. It needs national distribution data, and the cohort is small and non-random.
   Noted as a possible next step.

Details: the tables are parsed directly from GOV.UK HTML by a script, not transcribed by an LLM,
to avoid hallucinated numbers. A web-summary pass was cross-checked: anchors Reading 28→100,
GPS 35→100 and Maths 58→100 match Schools Week. Interpolate between raw marks for smoothness.
Floor "no scaled score" marks (0–2) at 80. English averages Reading and GPS, because the hierarchy
has no topic names to split them. A dense 0.1% lookup table keeps the scoring join simple and inspectable.

## 3. Aggregation rule

- Single latest sitting: too noisy. Sittings can be 8 questions.
- All-time pooled: hides progress, and mixes Year 1 work into a Year 3 score.
- Trailing time window (e.g. 365 days): scores would change when old sittings expire, not only when
  new evidence arrives. That complicates the SCD2 history, which would need expiry events.
- **Latest N=3 sittings, pooled by question: chosen.** Scores only change on new evidence, so the
  history is a clean event-driven type 2 table. N is a parameter.
- A minimum of 10 questions is required to award a score. Below that the status is `insufficient_evidence`.

## 4. Table design

- **Layering:** staging views, then an incremental sitting-level table, then marts.
  The sitting layer is the scale lever: about 30× fewer rows than responses.
- **Incremental pattern:** delete and re-insert the affected sessions in a transaction, rather than
  MERGE. It is simpler, idempotent, and correctly removes rows if a question's subject mapping changes.
- **Point-in-time:** an SCD2 history plus a table function for "as of" queries. The current table is
  the table function at the end of time, so they cannot drift.
- **App table:** flat, typed, NOT NULL where possible, declared PK, status enum, model version.
  One row per pupil × subject, even without evidence, so the app never infers "missing".
- **Determinism:** no `CURRENT_TIMESTAMP` in data, and explicit tie-breaks everywhere.
  `ROW_NUMBER` ties are broken by `session_id`.
- **Tests:** BigQuery `ASSERT` statements run as the last build step. An idempotency check compares
  `BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(row)))` per table across two runs.

## 5. Issues hit during the build

- A BigQuery syntax error: `QUALIFY` must come before the named `WINDOW` clause, and window frame
  offsets must be literals. Fixed by rendering `{{rolling_sittings_preceding}}` in the runner.
- Verification: the full build passed all twelve assertions. Two consecutive builds gave identical
  fingerprints. An incremental run from 2026-06-01 (786 rows replaced) reproduced the full-build
  fingerprint exactly.

## 6. Out of scope / next steps

These are listed in README §6: per-assessment calibration, splitting English by component,
uncertainty bands, fixing duplicate events at source, ingestion timestamps, and dbt.

## 7. Change 2: every subject, labelled by mapping_type

- The brief's "every subject" was re-read literally. Rather than drop non-SATs subjects, each
  subject gets a `mapping_type` so the app can label proxy scores as estimates.
- The generic proxy curve is the equal-weight average of the Maths, Reading and GPS curves. It sits
  between the two official curves: 53% maps to 100, and 90% maps to 115.
- not_attainment is enforced in two places, the history and the table function. A survey sitting
  that someday passes eligibility still can't produce a score.
- The scoring logic is unchanged, so English and Maths output is identical to version 1.0.
