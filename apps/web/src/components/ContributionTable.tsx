"use client";

/**
 * The triage list for pasted envelopes.
 *
 * A table for the same reason ReportTable is one: triage is a scan down a column, and the
 * submitted text -- which can run to a full quest's worth of dialogue -- sits behind a
 * `<details>` so a long paste does not push every row after it off the screen (the reasoning
 * CATEGORY_COLUMN gives in lib/reports/reports.ts for the same shape of problem).
 *
 * Never renders `ip`, `name` or `email`: reports/ReportTable shows a reporter's own name
 * because they gave it to have their report followed up on, but a contribution's identifying
 * fields exist only for abuse response, not for triage to read. `body` -- the optional
 * complaint -- is different: it's the one field a player filled in specifically to be read,
 * so it is rendered below, deliberately included in the Row this component accepts.
 *
 * `initial` is typed as `ContributionRow`, not the full `Contribution`, and page.tsx must
 * project down to it before passing rows here: this is a "use client" component, so whatever
 * shape its props carry crosses into the RSC flight payload and is readable in devtools
 * regardless of what this file goes on to render. `ip`, `name`, `email` and `raw` have no
 * reason to make that crossing at all.
 */
import { useCallback, useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { ConfirmedFilter } from "@/app/contributions/page";
import type { ContributionStatus } from "@/lib/contributions/contributions";
import type { Contribution } from "@/lib/contributions/store";
// From npc.ts, not npc/store.ts: store.ts imports @/lib/db, and pulling PROVENANCES (a value,
// not just a type) out of it would drag Postgres's own node built-ins into this client bundle.
import { PROVENANCES, type Provenance } from "@/lib/npc/npc";
import type { NpcResolution } from "@/lib/npc/store";
import { cn } from "@/lib/utils";

/**
 * Who a row's NPC is, in exactly the shape this table renders -- the same Pick<> discipline as
 * ContributionRow below, for the same reason: `npcName`, `modelFileId`, `sex`, `creatureType`,
 * `build`, `note` and `resolvedBy` are on NpcResolution but never drawn here, so they stay out
 * of the flight payload.
 */
export type NpcSummary = Pick<
  NpcResolution,
  "npcKind" | "npcId" | "race" | "gender" | "flavor" | "provenance" | "confirmed"
>;

/** The fields this table reads. page.tsx projects full Contribution rows down to this shape. */
export type ContributionRow = Pick<
  Contribution,
  "id" | "source" | "key" | "locale" | "count" | "text" | "status" | "createdAt" | "body"
> & {
  /** Null when the envelope never named an NPC at all -- zones and books, or a quest keyed on quest+event. */
  npc: NpcSummary | null;
};

const SOURCE_LABELS: Record<Contribution["source"], string> = {
  quests: "Quests",
  zones: "Zones",
  books: "Books",
};

const STATUS_LABELS: Record<ContributionStatus, string> = {
  new: "New",
  accepted: "Accepted",
  rejected: "Rejected",
};

const STATUS_OPTIONS: readonly ContributionStatus[] = ["new", "accepted", "rejected"];

const PROVENANCE_LABELS: Record<Provenance, string> = {
  corpus: "Corpus",
  client: "Client guess",
  moderator: "Moderator",
  none: "No race",
};

const CONFIRMED_LABELS: Record<Exclude<ConfirmedFilter, "all">, string> = {
  confirmed: "Confirmed",
  unconfirmed: "Unconfirmed",
};
const CONFIRMED_OPTIONS: readonly Exclude<ConfirmedFilter, "all">[] = ["unconfirmed", "confirmed"];

/** The day and the clock time, short enough to sit in a column, matching ReportTable's `when`. */
function when(at: string): string {
  return new Date(at).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** "race-gender-flavor", or as much of it as is known -- a moderator can fill in the rest. */
function speaker(npc: NpcSummary): string {
  return [npc.race, npc.gender, npc.flavor].map((part) => part ?? "?").join("-");
}

/**
 * A row's speaker column must never read as a confident answer when it isn't one: `confirmed`
 * is the one column resolveNpc and the override route agree means "trust this", so it -- not
 * provenance alone -- is what this table shows plainly versus flags.
 *
 * A confirmed row with every field null is still a decision, not an absence -- a moderator (or
 * the corpus, for a narrator-style pseudo-race) looked and there is no race to assign. Left
 * unlabelled, "?-?-?" next to a "moderator" badge would be one small badge away from looking
 * identical to a genuinely unresolved "?-?-?"/"none" row, which defeats the point of this column
 * being a skimmable "still needs a human" signal.
 */
function speakerNote(npc: NpcSummary): string | null {
  if (npc.confirmed) {
    return npc.race || npc.gender || npc.flavor ? null : "confirmed: no race";
  }
  if (npc.provenance === "client") return "guessed from the model the client reported";
  return "not identified";
}

export default function ContributionTable({
  initial,
  status,
  provenance,
  confirmed,
  existing,
}: {
  initial: ContributionRow[];
  status: ContributionStatus | "all";
  provenance: Provenance | "all";
  confirmed: ConfirmedFilter;
  /** id -> corpus text, present only where the row's key resolves to something on file. */
  existing: Record<number, string>;
}) {
  /**
   * What this session resolved, overlaid on the server's rows -- the same shape ReportTable
   * uses and for the same reason: the status links below are navigations, so seeding state
   * from `initial` once would leave a resolved row sitting in a queue it no longer belongs to
   * until the next reload.
   */
  const [resolved, setResolved] = useState<Record<number, Contribution["status"]>>({});
  const [busy, setBusy] = useState<number | null>(null);

  /**
   * The npc column, overlaid on the server's rows for the same reason `resolved` is: the
   * override writes through to the NPC, not this contribution, so nothing here navigates away
   * on save and a reload would be the only other way to see it land.
   */
  const [npcOverrides, setNpcOverrides] = useState<Record<number, NpcSummary>>({});
  const [npcBusy, setNpcBusy] = useState<number | null>(null);

  const overrideNpc = useCallback(
    async (
      contributionId: number,
      npc: NpcSummary,
      answer: { race: string; gender: string; flavor: string; note: string },
    ) => {
      setNpcBusy(contributionId);
      const response = await fetch("/api/contributions/npc", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ npcKind: npc.npcKind, npcId: npc.npcId, ...answer }),
      }).catch(() => null);
      setNpcBusy(null);

      if (!response?.ok) return;
      const { resolution } = (await response.json()) as { resolution: NpcResolution };
      setNpcOverrides((current) => ({
        ...current,
        [contributionId]: {
          npcKind: resolution.npcKind,
          npcId: resolution.npcId,
          race: resolution.race,
          gender: resolution.gender,
          flavor: resolution.flavor,
          provenance: resolution.provenance,
          confirmed: resolution.confirmed,
        },
      }));
    },
    [],
  );

  const resolve = useCallback(async (id: number, next: ContributionStatus) => {
    setBusy(id);
    const response = await fetch("/api/contributions/resolve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id, status: next }),
    }).catch(() => null);
    setBusy(null);

    if (!response?.ok) return;
    setResolved((current) => ({ ...current, [id]: next }));
  }, []);

  const rows = initial.filter((row) => {
    const current = resolved[row.id] ?? row.status;
    return status === "all" || current === status;
  });

  // Combines whichever one of the three dimensions is changing with the other two as they
  // stand -- otherwise a click on a provenance link would reset status and confirmed back to
  // their defaults, undoing whatever else the moderator had already narrowed to.
  function href(next: { status?: ContributionStatus | "all"; provenance?: Provenance | "all"; confirmed?: ConfirmedFilter }) {
    const params = new URLSearchParams({
      status: next.status ?? status,
      provenance: next.provenance ?? provenance,
      confirmed: next.confirmed ?? confirmed,
    });
    return `/contributions?${params}`;
  }

  return (
    <>
      {/* Links rather than FilterChip's dropdown, matching /reports's own status filter: a
          queue is the thing collaborators want to jump between, not narrow through a dropdown.
          Three groups now, not one -- provenance and confirmed are what finding 5 asked for,
          the thing that makes an unconfirmed NPC guess revisitable later. */}
      <nav className="mb-4 flex flex-wrap items-center gap-2 text-sm">
        {STATUS_OPTIONS.map((option) => (
          <a
            key={option}
            href={href({ status: option })}
            className={cn(
              "rounded-full border px-3 py-1",
              status === option
                ? "border-primary bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted",
            )}
          >
            {STATUS_LABELS[option]}
          </a>
        ))}
        <a
          href={href({ status: "all" })}
          className={cn(
            "rounded-full border px-3 py-1",
            status === "all"
              ? "border-primary bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted",
          )}
        >
          All
        </a>
      </nav>

      <nav className="mb-4 flex flex-wrap items-center gap-2 text-sm">
        <span className="text-muted-foreground text-xs">Speaker:</span>
        {CONFIRMED_OPTIONS.map((option) => (
          <a
            key={option}
            href={href({ confirmed: confirmed === option ? "all" : option })}
            className={cn(
              "rounded-full border px-3 py-1",
              confirmed === option
                ? "border-primary bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted",
            )}
          >
            {CONFIRMED_LABELS[option]}
          </a>
        ))}
        {PROVENANCES.map((option) => (
          <a
            key={option}
            href={href({ provenance: provenance === option ? "all" : option })}
            className={cn(
              "rounded-full border px-3 py-1",
              provenance === option
                ? "border-primary bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted",
            )}
          >
            {PROVENANCE_LABELS[option]}
          </a>
        ))}
      </nav>

      {rows.length === 0 ? (
        <p className="text-muted-foreground text-sm">Nothing here.</p>
      ) : (
        <table className="w-full border-separate border-spacing-0 text-sm">
          <thead className="text-muted-foreground text-left text-xs">
            <tr>
              <th className="border-b py-2 pr-3 font-normal">Filed</th>
              <th className="border-b py-2 pr-3 font-normal">Where</th>
              <th className="border-b py-2 pr-3 font-normal">Locale</th>
              <th className="border-b py-2 pr-3 font-normal">Count</th>
              <th className="border-b py-2 pr-3 font-normal">What they sent</th>
              <th className="border-b py-2 pr-3 font-normal">Speaker</th>
              <th className="border-b py-2 pr-3 font-normal">Status</th>
              <th className="border-b py-2 font-normal" />
            </tr>
          </thead>

          <tbody>
            {rows.map((row) => {
              const current = resolved[row.id] ?? row.status;
              const found = existing[row.id];
              const npc = npcOverrides[row.id] ?? row.npc;

              return (
                <tr key={row.id} className="align-middle [&>td]:border-b [&>td]:py-2 [&>td]:leading-5">
                  <td className="text-muted-foreground pr-3 text-xs whitespace-nowrap">
                    {when(row.createdAt)}
                  </td>

                  <td className="max-w-[16rem] pr-3 text-xs">
                    <div className="flex items-center gap-2 overflow-hidden whitespace-nowrap">
                      <Badge variant="outline" className="shrink-0 py-0 leading-5">
                        {SOURCE_LABELS[row.source]}
                      </Badge>
                      <span className="truncate font-mono" title={row.key}>
                        {row.key}
                      </span>
                    </div>
                  </td>

                  <td className="pr-3 text-xs whitespace-nowrap">{row.locale}</td>

                  <td className="pr-3 text-xs whitespace-nowrap">{row.count}</td>

                  <td className="max-w-md pr-3">
                    {/* Collapsed by default: a full quest's dialogue in an open cell is the
                        "table stops being a scan" failure this markup exists to avoid. */}
                    <details>
                      <summary className="text-muted-foreground cursor-pointer text-xs">
                        {row.text ? `${row.text.length} chars` : "no text"}
                        {found !== undefined ? " · corpus already has this key" : ""}
                        {row.body ? " · note attached" : ""}
                      </summary>
                      <p className="mt-1 whitespace-pre-wrap">{row.text ?? "(no text sent)"}</p>
                      {row.body ? (
                        // The optional complaint: collected on the form, stored as `body`, and
                        // until now rendered nowhere -- a player who explained what was wrong
                        // had that reach no one. Shown here rather than its own column because
                        // most rows won't have one and a column that's usually empty is a scan
                        // slower than the details cell it would sit next to.
                        <div className="mt-2 rounded border p-2">
                          <p className="text-muted-foreground text-xs font-medium">
                            What they said was wrong:
                          </p>
                          <p className="mt-1 whitespace-pre-wrap">{row.body}</p>
                        </div>
                      ) : null}
                      {found !== undefined ? (
                        // A "missing" key the corpus already answers to is a corpus bug, not
                        // an absent line -- shown beside the submitted text so that reading is
                        // a glance, not a second lookup.
                        <div className="bg-muted/40 mt-2 rounded p-2">
                          <p className="text-muted-foreground text-xs font-medium">
                            Already on file:
                          </p>
                          <p className="mt-1 whitespace-pre-wrap">{found}</p>
                        </div>
                      ) : null}
                      {npc ? (
                        <NpcOverrideForm
                          npc={npc}
                          busy={npcBusy === row.id}
                          onSave={(answer) => void overrideNpc(row.id, npc, answer)}
                        />
                      ) : null}
                    </details>
                  </td>

                  <td className="pr-3 text-xs whitespace-nowrap">
                    {npc ? (
                      <>
                        <span>{speaker(npc)}</span>
                        <Badge variant="outline" className="ml-1 py-0 leading-5">
                          {npc.provenance}
                        </Badge>
                        {speakerNote(npc) ? (
                          <p className="text-muted-foreground mt-0.5">{speakerNote(npc)}</p>
                        ) : null}
                      </>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </td>

                  <td className="pr-3 text-xs whitespace-nowrap">{STATUS_LABELS[current]}</td>

                  <td>
                    <div className="flex items-center justify-end gap-1">
                      {current !== "accepted" ? (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === row.id}
                          onClick={() => void resolve(row.id, "accepted")}
                        >
                          Accept
                        </Button>
                      ) : null}
                      {current !== "rejected" ? (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === row.id}
                          onClick={() => void resolve(row.id, "rejected")}
                        >
                          Reject
                        </Button>
                      ) : null}
                      {current !== "new" ? (
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy === row.id}
                          onClick={() => void resolve(row.id, "new")}
                        >
                          Reopen
                        </Button>
                      ) : null}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </>
  );
}

/**
 * The override, inside the same `<details>` as the submitted text: race, gender, flavor and a
 * note, posted to /api/contributions/npc.
 *
 * Its own inputs rather than lifting them into the table's state -- a form per row, opened one
 * at a time, is exactly what `<details>` already scopes, and the table has no other reason to
 * know what a moderator is mid-typing in a row nobody has saved yet.
 */
function NpcOverrideForm({
  npc,
  busy,
  onSave,
}: {
  npc: NpcSummary;
  busy: boolean;
  onSave: (answer: { race: string; gender: string; flavor: string; note: string }) => void;
}) {
  const [race, setRace] = useState(npc.race ?? "");
  const [gender, setGender] = useState(npc.gender ?? "");
  const [flavor, setFlavor] = useState(npc.flavor ?? "");
  const [note, setNote] = useState("");

  return (
    <form
      className="mt-2 rounded border p-2"
      onSubmit={(event) => {
        event.preventDefault();
        onSave({ race, gender, flavor, note });
      }}
    >
      <p className="text-muted-foreground text-xs font-medium">
        Say who this is (empty clears a field):
      </p>
      <div className="mt-1 flex flex-wrap gap-2">
        <Input
          value={race}
          onChange={(event) => setRace(event.target.value)}
          placeholder="race"
          className="h-8 w-28 text-xs"
        />
        <Input
          value={gender}
          onChange={(event) => setGender(event.target.value)}
          placeholder="gender"
          className="h-8 w-24 text-xs"
        />
        <Input
          value={flavor}
          onChange={(event) => setFlavor(event.target.value)}
          placeholder="flavor"
          className="h-8 w-28 text-xs"
        />
        <Input
          value={note}
          onChange={(event) => setNote(event.target.value)}
          placeholder="why (e.g. a Wowhead link)"
          className="h-8 flex-1 text-xs"
        />
        <Button type="submit" size="sm" variant="outline" disabled={busy}>
          Save
        </Button>
      </div>
    </form>
  );
}
