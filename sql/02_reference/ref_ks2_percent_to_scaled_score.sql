-- ref_ks2_percent_to_scaled_score
-- Grain: one row per (sats_subject, percent_tenths) where percent_tenths is 0..1000
--        (i.e. percent correct to one decimal place).
--
-- Turns the official GOV.UK raw->scaled conversion tables (seed: ref_ks2_scaled_score_conversion)
-- into a percent->scaled curve:
--   1. a pupil's percent correct is mapped to the equivalent raw mark on the real KS2 paper
--      (percent x max raw mark, e.g. 60% of 110 = 66 marks in Maths);
--   2. the scaled score is linearly interpolated between the two neighbouring raw marks;
--   3. raw marks 0-2 have "no scaled score" on GOV.UK; we floor them at 80 (bottom of scale);
--   4. ENGLISH averages the Reading and GPS curves (see ref_sats_subjects).
-- Pre-computing a dense lookup keeps the scoring models a simple equi-join and makes the
-- curve itself easy to inspect, chart and version.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.ref_ks2_percent_to_scaled_score` AS
WITH conversion AS (
  SELECT
    source_year,
    test_code,
    raw_score,
    max_raw_score,
    COALESCE(scaled_score, 80) AS scaled_score
  FROM `{{project}}.{{dataset}}.ref_ks2_scaled_score_conversion`
  WHERE source_year = {{conversion_year}}
),

tests AS (
  SELECT DISTINCT source_year, test_code, max_raw_score FROM conversion
),

grid AS (
  SELECT
    t.source_year,
    t.test_code,
    p AS percent_tenths,
    p / 1000 * t.max_raw_score AS equivalent_raw_score
  FROM tests AS t
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 1000)) AS p
),

per_test AS (
  SELECT
    g.source_year,
    g.test_code,
    g.percent_tenths,
    lo.scaled_score
      + (g.equivalent_raw_score - lo.raw_score) * (hi.scaled_score - lo.scaled_score)
      AS scaled_score_unrounded
  FROM grid AS g
  JOIN conversion AS lo
    ON lo.test_code = g.test_code AND lo.raw_score = CAST(FLOOR(g.equivalent_raw_score) AS INT64)
  JOIN conversion AS hi
    ON hi.test_code = g.test_code AND hi.raw_score = CAST(CEIL(g.equivalent_raw_score) AS INT64)
)

SELECT
  s.sats_subject,
  pt.percent_tenths,
  pt.percent_tenths / 10                              AS percent_correct,
  ROUND(AVG(pt.scaled_score_unrounded), 2)            AS scaled_score_unrounded,
  CAST(ROUND(AVG(pt.scaled_score_unrounded)) AS INT64) AS scaled_score,
  ANY_VALUE(pt.source_year)                           AS conversion_source_year
FROM per_test AS pt
JOIN `{{project}}.{{dataset}}.ref_sats_subjects` AS s
  ON pt.test_code IN UNNEST(s.ks2_test_codes)
GROUP BY s.sats_subject, pt.percent_tenths;
