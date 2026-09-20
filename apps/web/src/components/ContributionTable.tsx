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
import type { ContributionStatus } from "@/lib/contributions/contributions";
import type { Contribution } from "@/lib/contributions/store";
import { cn } from "@/lib/utils";

/** The fields this table reads. page.tsx projects full Contribution rows down to this shape. */
export type ContributionRow = Pick<
  Contribution,
  "id" | "source" | "key" | "locale" | "count" | "text" | "status" | "createdAt" | "body"
>;

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

/** The day and the clock time, short enough to sit in a column, matching ReportTable's `when`. */
function when(at: string): string {
  return new Date(at).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default function ContributionTable({
  initial,
  status,
  existing,
}: {
  initial: ContributionRow[];
  status: ContributionStatus | "all";
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

  return (
    <>
      {/* Three links rather than FilterChip's dropdown: there is exactly one dimension to
          filter on here, where reports has three, and a queue is the thing collaborators
          want to jump between, not narrow. */}
      <nav className="mb-4 flex flex-wrap items-center gap-2 text-sm">
        {STATUS_OPTIONS.map((option) => (
          <a
            key={option}
            href={`/contributions?status=${option}`}
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
          href="/contributions?status=all"
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
              <th className="border-b py-2 pr-3 font-normal">Status</th>
              <th className="border-b py-2 font-normal" />
            </tr>
          </thead>

          <tbody>
            {rows.map((row) => {
              const current = resolved[row.id] ?? row.status;
              const found = existing[row.id];

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
                    </details>
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
