-- Who is speaking a contributed line.
--
-- The corpus answers this for every NPC it already carries. This table is for the ones it does
-- not: a quest from content that postdates the 1.12 world database the corpus is built from.
--
-- Keyed on the kind AND the id, never the id alone. Creature and gameobject ids are separate
-- spaces that overlap -- creature 68 is a Stormwind City Guard, gameobject 68 is a Wanted
-- Poster -- and lib/corpus.ts keys the corpus the same way for the same reason.
--
-- One row per NPC rather than per contribution, because several contributions share an NPC and
-- correcting it once should correct all of them.
--
-- "provenance" is what makes an unconfirmed row findable later: `client` means a model file id
-- was mapped and the flavor was defaulted, and a moderator may well know better.
--
-- Additive and forward-only: nothing here changes a table an earlier release reads.

create table if not exists "npc_resolution" (
  "npcKind"      text not null,
  "npcId"        integer not null,
  "npcName"      text,
  "race"         text,
  "gender"       text,
  "flavor"       text,
  "provenance"   text not null,
  "confirmed"    boolean not null default false,
  "modelFileId"  integer,
  "sex"          integer,
  "creatureType" text,
  -- Model ids are per-build client data, so the build that reported one is part of the claim.
  "build"        text,
  "note"         text,
  "resolvedBy"   text references "user" ("id") on delete set null,
  "updatedAt"    timestamptz not null default now(),
  primary key ("npcKind", "npcId"),
  constraint "npc_resolution_kind_check" check ("npcKind" in ('creature', 'gameobject')),
  constraint "npc_resolution_provenance_check"
    check ("provenance" in ('corpus', 'client', 'moderator', 'none'))
);

-- Triage reads the unconfirmed ones first; that is the queue this table exists to make.
create index if not exists "npc_resolution_unconfirmed_idx"
  on "npc_resolution" ("confirmed", "updatedAt" desc);
