# Prompts and AI workflow

## Tool

Claude Code, Anthropic's agentic command-line coding tool, running locally on Windows.
It had shell access to an authenticated Google Cloud SDK (`bq`) and web access for GOV.UK.

## Prompt

The full take-home brief was pasted into Claude Code, followed by one instruction in Lithuanian:

> "PADARYK SIA UZDUOTI SUKURDAMAS NAUJA PROJEKTA SU TAM ATITINKMAU PAVADINIMU."
> In English: "Do this task by creating a new project with an appropriate name."

## How the session ran

1. **Discovery.** The agent listed the datasets, read the table schemas, and ran about 30 profiling
   queries. It found the duplicates, orphan responses, invalid year groups, and the mismatched
   session types.
2. **External data.** The agent web-searched for the 2025 KS2 scaled-score tables. It then wrote
   `scripts/fetch_ks2_conversion_tables.py` to parse the GOV.UK HTML deterministically, rather than
   trusting a model's transcription. Published anchors were cross-checked.
3. **Design.** Options for the conversion, the aggregation window, and the incremental strategy were
   weighed. The decision log is in `planning.md`.
4. **Build.** The agent wrote the SQL models and runner, executed them against BigQuery, fixed a
   syntax error, and ran the assertion suite, the idempotency check, and an incremental-equivalence check.
5. **Validation.** It sanity-checked score distributions, conversion-curve anchors, and point-in-time
   results at several dates, and traced one pupil's full score history.
6. **Documentation.** README, data-quality table, assumptions, next steps, and the Step 3 answer.

## Human responsibilities

The candidate owns the final review of the assumptions, which are the judgement calls in README §3.
They also own pushing the repository to GitHub and sending the link.

## Change 2: score every Atom subject

### Prompt

A follow-up prompt pointed out that the brief asks for "a SATs score for every pupil, in every
subject", while only English and Maths were scored. It asked for every Atom subject to get a row,
without passing off non-SATs subjects as official SATs results. The existing scoring logic had to
stay; only the curve choice per subject could change. The prompt specified:

- check the data per subject first: right/wrong answers, sitting types, pupil and sitting counts;
- add a `mapping_type` to `ref_sats_subjects`: `official` for English and Maths, `proxy` for
  attainment subjects with right/wrong answers (generic curve = average of the three official KS2
  curves), and `not_attainment` for Wellbeing;
- review the eligibility rule for proxy subjects;
- carry `mapping_type` to the marts, and give not_attainment subjects NULL scores with
  `score_status = 'not_attainment'`;
- bump the model version, extend the tests, rebuild, and update the README.

### What the data check found

- Science has questions in the hierarchy but no responses at all.
- Verbal Reasoning, Non-Verbal Reasoning and Screeners have real right and wrong answers. All their
  sittings are complete, summative and fixed-question, so the eligibility rule needed no change.
- Wellbeing sittings are surveys. `is_correct` is filled in for them anyway, but a survey has no
  right answer, so Wellbeing stays not_attainment. This was added as a data-quality finding.

### What changed

- `ref_sats_subjects` covers all 7 subjects with `mapping_type`.
- The history, the as-of function and the app table expose `mapping_type`. The status
  `not_attainment` is enforced in both the history and the table function.
- `MODEL_VERSION` went from `ks2-v1.0` to `ks2-v1.1`.
- Three tests were added: every hierarchy subject is mapped, not_attainment rows never carry a
  score, and every scoreable subject has a complete curve. The row-count test now covers all subjects.
- One test failed on the first run. The "no scores before any data" test expected only
  `no_evidence`, but Wellbeing rows are always `not_attainment`. The test was corrected to allow both.
- Verification: all 15 tests passed, and two consecutive builds were identical. English and Maths
  results were unchanged.
