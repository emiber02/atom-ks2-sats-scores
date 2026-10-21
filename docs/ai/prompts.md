# Prompts and AI workflow

## How I used AI

I gave Claude Code the take-home brief and asked it to build the solution as a new project. It
profiled the data, built the first version of the models, materialised them in BigQuery and drafted
the docs. I reviewed the output. I questioned why only English and Maths were scored when the brief
asks for every subject, which led to the official / proxy / not_attainment mapping. I then ran the
review session below to challenge the main design decisions against the data. I sent the ten questions
together in one message. Claude answered them with read-only queries. I asked for no code changes in
this session, so recommendations are recorded here but not yet applied.

## Origin of the first version

The first version was generated from the take-home brief. I pasted the brief into Claude Code with a
one-line instruction to complete the task in a new, suitably named project.

## Review session

All numbers come from queries run against `atom-analytics-candidates` during this session. As a check,
the analysis recomputed every current score from raw responses and matched `pupil_sats_scores` with
0 mismatches out of 397 scored pupil-subject rows.

### 1. Understanding the data

> Before we change anything, I want to understand the raw data myself. Profile the four tables in
> de_raw: row counts, keys, grain, nulls, and how they join. Then list the data quality issues
> you see, ranked by how much they could affect a pupil's score. Show the queries.

The tables are `responses`, `assessment_sittings`, `pupils` and `course_hierarchy`. They hold
63,707 responses, 2,509 sittings, 242 pupils and 10,552 questions. Their keys are unique, and there
are no nulls in key columns. The issues, ranked by effect on scores:

| Rank | Issue | Effect on scores |
|---|---|---|
| 1 | Duplicate answers that disagree on `is_correct` | 850 conflicting questions in 528 official-subject sittings. The resolution rule moves scores by up to 4 points. See question 2. |
| 2 | Responses with no sitting record | 46 official-subject sittings and 1,146 questions are excluded. All 40 affected pupil-subjects still get a score from other sittings. |
| 3 | Complete English sittings with fewer answers than `total_questions` | 49 sittings, 53 missing questions, 97% answered on average. Negligible. |
| 4 | Incomplete sittings | 2 sittings excluded. Negligible. |
| 5 | `responses.session_type` always says MOCK_TEST | No effect, because the sitting is treated as the source of truth. |
| 6 | Year groups 14 and 15 | No effect. These are entrance exams with no responses. |
| 7 | Answers after `finished_at` | 236 sittings, all within 1 second. No effect. |

**Correction found in this session.** The README and `planning.md` say one answer arrived about
196 days late. That is wrong. The original profiling query had a bug: it compared answers with
`ANY_VALUE(finished_at)` across many sittings. The real maximum is 1 second. The README needs a fix.

The profiling queries are in `sql/analysis/data_quality_profile.sql`.

### 2. Duplicate answers

> For the duplicate answers that disagree on is_correct: give me the options (LOGICAL_AND, majority
> vote, any correct, latest by response_id) with pros and cons. Run a query showing how many pupil
> scores would change under each option. I'll decide which one we keep.

The duplicates share identical `answered_at` and `seconds_taken`, so time cannot break the tie.

- **LOGICAL_AND (current):** conservative and deterministic. It may under-credit a pupil if the bug duplicates a correct answer as wrong.
- **Majority vote:** intuitive, but a 2-row split is a tie, so it needs a tie rule anyway.
- **Any correct:** generous. It rewards whatever produced the duplicate.
- **Latest by response_id:** looks natural, but the IDs are random UUIDs, so in practice this is a random pick.

Change against LOGICAL_AND, using the latest 3 sittings:

| Rule | English changed | Maths changed | Largest change | Pupils crossing 100 |
|---|---|---|---|---|
| Majority, ties count as wrong | 16 of 153 | 11 of 151 | 2 | 1 |
| Latest by response_id | 55 | 37 | 3 | 7 |
| Any correct | 80 | 69 | 4 | 14 |

Verbal Reasoning moves most under "any correct", by 5.6 points on average across 8 pupils, because
5 of its sittings are heavily duplicated. Screeners and Non-Verbal Reasoning have no conflicting duplicates.

**Decision:** keep LOGICAL_AND. It is the only rule that does not depend on an arbitrary tie-break.
Its difference from majority vote is small: at most 2 points, and 1 pupil crosses the expected standard.
The real fix is upstream: the duplicates look like a logging or retry bug.

### 3. What counts as evidence

> Which sittings should count towards a score? Show me the breakdown by session_type, style and
> completion status, and propose an eligibility rule. Flag anything ambiguous I need to decide.

Sittings with responses are almost all `summative_assessment` with style `fixed_question`. There are
1,025 English, 694 Maths, 568 Screeners, 13 Verbal Reasoning and 3 Non-Verbal Reasoning sittings
of this kind. The exceptions are 125 Wellbeing `survey` sittings, 2 incomplete sittings, and 56
sessions with no sitting record. `entrance_exam` and `mock_session` sittings have no responses.
The rule stays as it is: complete, not deleted, summative, fixed-question.

Ambiguities flagged for a decision:

- **Orphan responses:** 1,146 official-subject questions could be scored using answer timestamps alone. They are excluded now because completeness can't be checked.
- **Missing answers in 49 English sittings:** these are scored on the answers present. Treating the gaps as wrong is the alternative. The difference is negligible.
- **Screeners:** 11.8% of Screener questions are not attempted, against 2–5% elsewhere. They count as wrong. See question 5.

### 4. Converting to 80–120

> Explain the options for mapping percent correct to the 80-120 scale: linear, official GOV.UK
> raw-to-scaled tables, and percentile linking to national results. Which external data does each
> need, and what are the risks? Show me the resulting curve for the option we use, with anchors at
> 25%, 50%, 53%, 70% and 90%.

- **Linear:** needs no external data. It is wrong in shape. It puts 100 at 50%, but the real threshold is about 53%. It gives 116 at 90%, against 112 for real Maths.
- **Official GOV.UK tables (used):** needs the published raw-to-scaled tables. They are non-linear, current and explainable. The risk is assuming Atom percentages behave like KS2 paper percentages.
- **Percentile linking:** needs the national distribution of scaled scores. It assumes Atom's cohort is nationally representative, which is unlikely for a self-selected user base.

| % correct | English | Maths | Proxy |
|---|---|---|---|
| 25% | 90 | 92 | 91 |
| 50% | 99 | 99 | 99 |
| 53% | 100 | 100 | 100 |
| 70% | 106 | 104 | 105 |
| 90% | 117 | 112 | 115 |

No change.

### 5. Subjects

> The brief says every subject. Go through each subject in the hierarchy: does it have right/wrong
> answers, how much data is there, and does an official KS2 scale exist for it? Recommend how each
> should be scored, and explain the trade-off of scoring non-SATs subjects at all.

| Subject | Right/wrong answers | Data | Official KS2 scale | Mapping |
|---|---|---|---|---|
| English, Maths | yes | 153 and 151 pupils | yes | official |
| Screeners | yes | 82 pupils, 568 sittings | no | proxy |
| Verbal Reasoning | yes | 8 pupils, 13 sittings | no | proxy |
| Non-Verbal Reasoning | yes | 3 pupils, 3 sittings | no | proxy |
| Science | no responses yet | 0 | no, teacher-assessed | proxy, unused |
| Wellbeing | survey, no right answer | 129 pupils | no | not_attainment |

The trade-off: a proxy score gives teachers one familiar scale across subjects. But it can be mistaken
for a real SATs result. That is why `mapping_type` is exposed on every row.

The Screeners question from my shorter list was "Is the proxy curve for Screeners defensible?" The answer:

| Subject | Pupils | Mean | SD | Median | Mean % correct |
|---|---|---|---|---|---|
| English | 153 | 101.7 | 6.5 | 101 | 56.9 |
| Maths | 151 | 100.6 | 5.7 | 100 | 56.1 |
| Screeners | 82 | 100.8 | 6.2 | 101 | 55.5 |

Screener scores correlate with English at 0.70 and with Maths at 0.65, about as strongly as English
and Maths correlate with each other (0.65). Two things look off. Screeners have only 8 assessments,
all in Years 3–6, and every pupil sits a fixed battery of 7. Their no-attempt rate is 11.8%, about
three times higher than other subjects. That suggests timed tests where unreached questions count
as wrong, which pulls their percentages down. **Decision:** the proxy is defensible as a labelled
estimate. The no-attempt treatment for Screeners should be checked with the product team.

### 6. How many sittings to pool

> Compare scoring rules on our data: latest 1 sitting, latest 3, latest 5, and all-time pooled.
> How many pupils change score and by how much? Also check the minimum-questions threshold of 10.
> Recommend defaults and explain why.

Change against the current rule of the latest 3, for English and Maths with 304 pupil-subjects:

| Rule | Changed | Mean absolute change | Largest | Pupils crossing 100 |
|---|---|---|---|---|
| Latest 1 | 213 | 2.05 | 17 | 35 |
| Latest 5 | 189 | 0.88 | 5 | 13 |
| All-time | 188 | 0.98 | 6 | 19 |

A better test is to predict each pupil's next sitting from the sittings before it. This used 409
target sittings, the same for every rule.

| Rule | Average error on next sitting | Within 3 points | Average jump per new sitting |
|---|---|---|---|
| Latest 1 | 4.15 | 54% | 4.18 |
| Latest 3 | 3.48 | 61% | 1.48 |
| Latest 5 | 3.33 | 66% | 1.12 |
| All-time | 3.27 | 68% | 1.01 |

The minimum of 10 questions never applies on this data. The smallest pooled total is 25 questions
with the latest 3, and 12 with the latest 1.

**Recommendation:** change the default to the latest 5. It predicts the next sitting better than 3
and is more stable. It still drops old work, unlike all-time pooling. All-time looks best here only
because the data covers less than one school year. Over several years it would mix Year 2 work into
a Year 5 score. This is a one-setting change (`ROLLING_SITTINGS=5`). Not applied in this session.
Keep the minimum of 10 as a safeguard.

### 7. Point-in-time

> Explain the point-in-time design: why an SCD2 history plus a table function rather than daily
> snapshots? Show me one pupil's full history, and what happens when a late answer arrives.

A score only changes when a new sitting arrives. SCD2 stores one row per change: 2,303 rows today.
Daily snapshots would store every pupil and subject every day, mostly unchanged. They would also
only answer "as of midnight". The table function returns the score at any timestamp. The app table
is the same function at the end of time, so "current" and "historical" can't disagree.

Pupil `01b5275e…` shows the history working. Their English score moved 83 → 85 → 88 → 90 → 93 →
94 → 90 over nine versions from November 2025 to May 2026. Each version starts when a sitting
became available.

Late answers: `available_at` is the later of the finish time and the last answer, so a score never
appears before its evidence existed. In this data the latest answer is 1 second after finish. If a
genuinely late answer arrives, the incremental run recomputes that sitting and the history is
rebuilt. Its version then starts at the later time. The weakness is that history is rebuilt, not
appended. A past as-of query can change after late data arrives. That answers "what was true at T",
not "what did the dashboard show at T". The latter needs ingestion timestamps, which the raw tables
don't have.

### 8. Scale

> Responses will grow by 100m+ rows. Walk me through what a daily incremental run scans, how
> partitioning and clustering help, what it would cost, and what we'd change at 1bn rows.

Dry runs show the incremental filter scans 5.35 MB, about 84 bytes per row. That is the whole of
raw `responses`, because the staging view de-duplicates the full table before the date filter
applies. Raw `responses` is not partitioned, so nothing can be pruned. The load then reads the
touched sessions again.

The filter reads about 84 bytes per row. The load reads the full row, about 189 bytes, so a run
scans roughly 270 bytes per raw row.

| Responses | Estimated scan per daily run | On-demand cost per run, at $6.25 per TiB |
|---|---|---|
| 100m | about 27 GB | about $0.16 |
| 1bn | about 270 GB | about $1.60 |

These are linear extrapolations from the dry runs. Cost is not the problem. A full GROUP BY over
1bn rows every day is slow and slot-heavy.

At 1bn rows I would make five changes:

- partition raw `responses` on `DATE(answered_at)` and cluster it by `session_id`;
- make de-duplication an incremental table, not a view;
- detect touched sessions from recent partitions only;
- rebuild history only for touched pupils;
- MERGE into the app table instead of replacing it.

Downstream tables are already partitioned and clustered. `int_sitting_subject_results` is about
30 times smaller than `responses`.

### 9. App table and tests

> Review pupil_sats_scores as a table to migrate into an app database: types, keys, nullability,
> enums. Then review the test suite: what important failure would it NOT catch? Add a test if
> something is missing.

The table is flat and typed, with `NOT NULL` where a value always exists, a declared primary key,
enum-like status columns and a model version. Recommendations for migration:

- **`sats_subject`** now also holds WELLBEING and proxy subjects. `subject_code` would be a more honest name.
- **`percent_correct`** should be a fixed-precision number in the app database, not a float.
- **`score_status` and `mapping_type`** should become database enums or CHECK constraints.
- **`score_history_id`** points at a warehouse-only table. Keep it as a trace ID, not a foreign key.
- **Load timestamp.** The loader, not the model, should add a load timestamp, so the model stays idempotent.

Gaps in the test suite:

- **Curve anchors.** A comment says the curve is "anchored to the published expected standard", but no test checks this. A wrong seed file, for example a different year's table, would pass.
- **Lost sittings.** No test checks that every scoreable sitting reaches the history. A broken join could silently drop sittings.
- **Facts in the docs.** The 196-day error shows that numbers quoted in docs are not tested.

**Recommendation:** add two assertions, one for the seed anchors (Reading 28, GPS 35 and Maths 58
map to 100) and one for sitting coverage. Not added in this session, because I asked for no code changes.

### 10. Documentation

> Update docs/ai/prompts.md: add a section "Review session" listing the questions I asked in this
> session, in my words, with a one or two sentence summary of each answer and any decision or
> change it led to. Replace the verbatim Lithuanian instruction with a plain English description
> that the first version was generated from the brief, and add a short first-person "How I used AI"
> paragraph. Record only what actually happened. Rebuild, run tests, commit and push.

This file is the result. No code or tables changed in this session, so no rebuild was needed. The
15 tests last passed after the subject-mapping change.

## Open actions from this session

1. Fix the 196-day claim in README data-quality item 5 and in `planning.md`.
2. Change `ROLLING_SITTINGS` to 5 and rebuild.
3. Add the curve-anchor and sitting-coverage tests.
4. Check with the product team how unattempted Screener questions should be scored.
