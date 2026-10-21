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
