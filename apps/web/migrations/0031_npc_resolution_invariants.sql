-- Two states 0030 left insertable that should not be.
--
-- "confirmed" is a claim that a human or the corpus itself stands behind. A "client" row is a
-- guess from a model file id mapping -- exactly the kind of guess this table exists to flag for
-- review -- so a client row that is also "confirmed" defeats the queue the unconfirmed index
-- was built to serve. Only "corpus" and "moderator" ever earn that flag.
--
-- "none" means the resolution attempt came up empty: no corpus hit, no client observation, no
-- moderator override. A "none" row carrying a race, gender or flavor is a contradiction --
-- claiming both "resolved to this" and "resolved to nothing" -- and would read as a real answer
-- to anything that trusts a non-null column over the provenance label.
--
-- Named explicitly, as 0028 explains: `drop constraint if exists` on a name Postgres did not
-- choose silently leaves the old constraint in place, so a rename or a widen would never take
-- effect. These are new constraints, but the same habit applies from the start.
--
-- Additive and forward-only: every row 0030 could have produced under its own constraints is
-- unaffected unless it already violated one of these, and none can have, since the table has
-- carried no rows a person filed from the game.

alter table "npc_resolution"
  add constraint "npc_resolution_confirmed_provenance_check"
    check (not "confirmed" or "provenance" in ('corpus', 'moderator'));

alter table "npc_resolution"
  add constraint "npc_resolution_none_is_empty_check"
    check ("provenance" <> 'none' or ("race" is null and "gender" is null and "flavor" is null));
