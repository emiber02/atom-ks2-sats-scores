-- ref_sats_subjects
-- Grain: one row per Atom subject that has a KS2 SATs equivalent.
--
-- Only English and Maths have a KS2 scaled score (80-120). Science is teacher-assessed
-- and has no scaled score; Verbal/Non-Verbal Reasoning are 11+ subjects; Screeners and
-- Wellbeing are not attainment measures. Those subjects get no SATs score by design.
--
-- KS2 English is two separate tests (Reading, and Grammar, Punctuation & Spelling).
-- Atom's "English" subject covers both and the hierarchy exposes no topic names to split
-- them, so the English conversion uses the average of the two official curves.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.ref_sats_subjects` AS
SELECT * FROM UNNEST([
  STRUCT(
    'f9b8238c-7181-42e5-8f9b-d25096efaae9' AS subject_id,
    'English'                              AS subject_name,
    'ENGLISH'                              AS sats_subject,
    ['ENGLISH_READING', 'ENGLISH_GPS']     AS ks2_test_codes),
  STRUCT(
    '682f6d8b-882e-4102-8042-14850c5f4c7c',
    'Maths',
    'MATHS',
    ['MATHS'])
]);
