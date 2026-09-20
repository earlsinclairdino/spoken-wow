-- Text a player sent because this corpus does not have it.
--
-- Separate from "report" rather than a seventh category on it. A report is a person waiting
-- for an answer about a line that exists; this is a line that does not, carrying a payload, and
-- the two are worked through differently -- triage on a report ends in a fix, triage here ends
-- in corpus.
--
-- "key" is a triage key and never a frozen line id: a page this corpus has never seen has no
-- pageTextID to be named by, so books keys on the checksum the client computed.
--
-- The unique index on "dedup" is what makes "count" a priority ranking: the same text from a
-- second player bumps it rather than filing a second row. DIFFERENT text for the same key is
-- deliberately a separate row -- mistranslation and vandalism belong beside the honest version,
-- not on top of it.
--
-- Additive and forward-only: nothing here changes a table an earlier release reads.

create table if not exists "contribution" (
  "id"         serial primary key,
  "source"     text not null,
  "key"        text not null,
  "locale"     text not null default 'enUS',
  "build"      text not null default '',
  "text"       text,
  "meta"       jsonb not null default '{}'::jsonb,
  "raw"        text not null,
  "dedup"      text not null,
  "count"      integer not null default 1,
  "status"     text not null default 'new',
  "body"       text,
  "name"       text,
  "email"      text,
  "userId"     text references "user" ("id") on delete set null,
  "ip"         text,
  "createdAt"  timestamptz not null default now(),
  "updatedAt"  timestamptz not null default now(),
  "resolvedBy" text references "user" ("id") on delete set null,
  constraint "contribution_source_check" check ("source" in ('quests', 'zones', 'books')),
  constraint "contribution_status_check" check ("status" in ('new', 'accepted', 'rejected'))
);

create unique index if not exists "contribution_dedup_idx" on "contribution" ("dedup");

-- Triage reads by status, newest and most-wanted first.
create index if not exists "contribution_status_idx" on "contribution" ("status", "count" desc, "createdAt" desc);

-- Every accepted paste, one row, for the rate limiter alone.
--
-- The limiter cannot count "contribution" rows: the upsert above collapses the same text from
-- ten people into one row with count 10, so a flood would read as a single submission and the
-- limit would never bite. What is being limited is how much one person sends, which is what
-- this table counts.
--
-- Nothing reads it but the limiter, so it carries no payload and nothing references it.
create table if not exists "contribution_hit" (
  "id"        serial primary key,
  "ip"        text,
  "createdAt" timestamptz not null default now()
);

create index if not exists "contribution_hit_ip_idx" on "contribution_hit" ("ip", "createdAt");
