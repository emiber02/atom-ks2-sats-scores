#!/usr/bin/env bash
# Build every model, in dependency order, into a BigQuery dataset.
#
# Usage:
#   scripts/build.sh                  # full build into the default dataset
#   DATASET=my_dev scripts/build.sh   # build into another dataset
#   INCREMENTAL_SINCE='2026-09-01' scripts/build.sh   # incremental refresh of the sitting layer
#   scripts/build.sh --check-idempotency            # build twice and compare table fingerprints
#
# Requires the Google Cloud SDK (bq) authenticated with access to PROJECT.
set -euo pipefail

PROJECT="${PROJECT:-atom-analytics-candidates}"
RAW_DATASET="${RAW_DATASET:-de_raw}"
DATASET="${DATASET:-emilija_bernotaite}"
INCREMENTAL_SINCE="${INCREMENTAL_SINCE:-1970-01-01}"
CONVERSION_YEAR="${CONVERSION_YEAR:-2025}"
ROLLING_SITTINGS="${ROLLING_SITTINGS:-3}"
MIN_QUESTIONS="${MIN_QUESTIONS:-10}"
MODEL_VERSION="${MODEL_VERSION:-ks2-v1.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

render() {
  sed -e "s/{{project}}/${PROJECT}/g" \
      -e "s/{{raw_dataset}}/${RAW_DATASET}/g" \
      -e "s/{{dataset}}/${DATASET}/g" \
      -e "s/{{incremental_since}}/${INCREMENTAL_SINCE}/g" \
      -e "s/{{conversion_year}}/${CONVERSION_YEAR}/g" \
      -e "s/{{rolling_sittings}}/${ROLLING_SITTINGS}/g" \
      -e "s/{{rolling_sittings_preceding}}/$((ROLLING_SITTINGS - 1))/g" \
      -e "s/{{min_questions}}/${MIN_QUESTIONS}/g" \
      -e "s/{{model_version}}/${MODEL_VERSION}/g" \
      "$1"
}

run_sql() {
  echo "-> $1"
  render "$ROOT/$1" | bq query --quiet --project_id="$PROJECT" --use_legacy_sql=false --format=none
}

load_seed() {
  echo "-> seed ks2_scaled_score_conversion"
  bq load --quiet --project_id="$PROJECT" --replace --source_format=CSV --skip_leading_rows=1 \
    "${DATASET}.ref_ks2_scaled_score_conversion" \
    "$ROOT/seeds/ks2_scaled_score_conversion.csv" \
    source_year:INTEGER,test_code:STRING,raw_score:INTEGER,max_raw_score:INTEGER,scaled_score:INTEGER
}

build() {
  run_sql sql/01_staging/stg_pupils.sql
  run_sql sql/01_staging/stg_assessment_sittings.sql
  run_sql sql/01_staging/stg_course_hierarchy.sql
  run_sql sql/01_staging/stg_responses.sql
  load_seed
  run_sql sql/02_reference/ref_sats_subjects.sql
  run_sql sql/02_reference/ref_ks2_percent_to_scaled_score.sql
  run_sql sql/03_intermediate/int_sitting_subject_results__ddl.sql
  run_sql sql/03_intermediate/int_sitting_subject_results.sql
  run_sql sql/04_marts/fct_pupil_sats_score_history.sql
  run_sql sql/04_marts/tvf_pupil_sats_scores_as_of.sql
  run_sql sql/04_marts/pupil_sats_scores.sql
  run_sql sql/05_tests/assert_models.sql
}

fingerprint() {
  # Order-independent hash of every row in each built table.
  local q=""
  for t in int_sitting_subject_results fct_pupil_sats_score_history pupil_sats_scores ref_ks2_percent_to_scaled_score; do
    q+="${q:+ UNION ALL }SELECT '$t' AS tbl, COUNT(*) AS n, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS fp FROM \`${PROJECT}.${DATASET}.$t\` t"
  done
  bq query --quiet --project_id="$PROJECT" --use_legacy_sql=false --format=csv "$q ORDER BY tbl"
}

build
echo "Build complete: ${PROJECT}.${DATASET}"

if [[ "${1:-}" == "--check-idempotency" ]]; then
  first="$(fingerprint)"
  build
  second="$(fingerprint)"
  echo "$first"
  if [[ "$first" == "$second" ]]; then echo "IDEMPOTENT: identical results after a second run"; else echo "NOT IDEMPOTENT"; echo "$second"; exit 1; fi
fi
