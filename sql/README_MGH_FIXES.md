# Historical Site A Notes

The canonical SQL path is now `RUN_ALL_enhanced.sql` with schema variables and
validated concept sets in `03_create_concept_sets.sql`.

Older MGH/Site A-specific fixes have been folded into the canonical files or
moved behind explicit local concept-set entries. Keep new site-specific concept
IDs in `concept_set_members` with `local_allowed = true` and a clear note.
