-- ref_sats_subjects
-- Grain: one row per Atom subject (every subject in stg_course_hierarchy).
--
-- mapping_type says how far a subject's score can be read as a SATs score:
--   official        English and Maths. Real KS2 tests with published GOV.UK conversion tables.
--                   KS2 English is two tests (Reading, and Grammar, Punctuation & Spelling).
--                   The hierarchy has no topic names to split them, so English averages both curves.
--   proxy           Attainment subjects with right/wrong answers but no KS2 scaled score.
--                   Science is teacher-assessed at KS2, VR and NVR are 11+ subjects, and
--                   Screeners are diagnostic. They use a generic KS2 curve: the average of all
--                   three official curves. Read it as "a percentage on an Atom assessment means
--                   roughly what it means on a typical KS2 paper". Not an official SATs result.
--   not_attainment  Wellbeing. Survey items with no right answers. No curve, never scored.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.ref_sats_subjects` AS
SELECT * FROM UNNEST([
  STRUCT(
    'f9b8238c-7181-42e5-8f9b-d25096efaae9' AS subject_id,
    'English'                              AS subject_name,
    'ENGLISH'                              AS sats_subject,
    'official'                             AS mapping_type,
    ['ENGLISH_READING', 'ENGLISH_GPS']     AS ks2_test_codes),
  STRUCT('682f6d8b-882e-4102-8042-14850c5f4c7c', 'Maths',                'MATHS',                'official',       ['MATHS']),
  STRUCT('c1093070-21b9-4ce5-89f4-d96e73c27fc8', 'Science',              'SCIENCE',              'proxy',          ['MATHS', 'ENGLISH_READING', 'ENGLISH_GPS']),
  STRUCT('574c5cbf-b2e4-4e0c-8e05-d13b832c76a1', 'Verbal Reasoning',     'VERBAL_REASONING',     'proxy',          ['MATHS', 'ENGLISH_READING', 'ENGLISH_GPS']),
  STRUCT('0976743b-3f5f-43fa-8ddb-4ceb8ae57691', 'Non-Verbal Reasoning', 'NON_VERBAL_REASONING', 'proxy',          ['MATHS', 'ENGLISH_READING', 'ENGLISH_GPS']),
  STRUCT('5e9914fd-b704-4e5e-8c54-85a12a381460', 'Screeners',            'SCREENERS',            'proxy',          ['MATHS', 'ENGLISH_READING', 'ENGLISH_GPS']),
  STRUCT('e07cba48-c761-429c-8bba-2bdb9770b5a4', 'Wellbeing',            'WELLBEING',            'not_attainment', ARRAY<STRING>[])
]);
