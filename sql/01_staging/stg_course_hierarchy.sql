-- stg_course_hierarchy
-- Grain: one row per question_id.
-- Places each question in subject > topic > subtopic > atom.
CREATE OR REPLACE VIEW `{{project}}.{{dataset}}.stg_course_hierarchy` AS
SELECT
  question_id,
  atom_id,
  subtopic_id,
  topic_id,
  subject_id,
  subject_name
FROM `{{project}}.{{raw_dataset}}.course_hierarchy`
WHERE question_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY question_id ORDER BY subject_id, topic_id, subtopic_id, atom_id) = 1;
