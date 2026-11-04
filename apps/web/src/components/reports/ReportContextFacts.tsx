/**
 * What the player's addon said it saw when Report was pressed: the facts, then the text.
 *
 * Shown as the player's claim, never as the line: the fragment is written by a client, and a
 * hand-edited link is as easy to send as a real one.
 */
"use client";

import { useState, type ReactNode } from "react";

import {
  LATEST_VERSION,
  addonLabel,
  contextFacts,
  outdatedVersion,
  type ReportContext,
} from "@/lib/reports/context";
import { cn } from "@/lib/utils";

export default function ReportContextFacts({
  context,
  className,
}: {
  context: ReportContext;
  className?: string;
}) {
  const facts = contextFacts(context);
  return (
    <div className={cn("flex flex-col gap-2 text-xs", className)}>
      {facts.length ? (
        <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5">
          {facts.map((fact) => (
            <div key={fact.label} className="contents">
              <dt className="text-muted-foreground">{fact.label}</dt>
              <dd className="break-words">{fact.value}</dd>
            </div>
          ))}
        </dl>
      ) : null}
      {context.text ? (
        <blockquote className="border-l-2 pl-2 text-sm break-words whitespace-pre-wrap">
          {context.text}
        </blockquote>
      ) : null}
    </div>
  );
}

/**
 * The context folded under a report in triage: the addon version on the summary line, and
 * that the line might already be fixed when a newer release is out. Might, because the
 * version says nothing about whether the release touched this line.
 *
 * `children` follow the facts and are drawn only once the context is opened, so what they fetch
 * is fetched for the reports somebody reads rather than for every row on the page.
 */
export function ReportContextNote({ context, children }: { context: ReportContext | null; children?: ReactNode }) {
  const [open, setOpen] = useState(false);
  if (!context) return null;
  const version = addonLabel(context) ?? "the game";
  const outdated = outdatedVersion(context);
  return (
    <details
      className="mt-1 text-xs"
      onClick={(event) => event.stopPropagation()}
      onToggle={(event) => setOpen(event.currentTarget.open)}
    >
      <summary className="text-muted-foreground cursor-pointer">
        From {version}
        {outdated ? (
          <span className="text-amber-600 dark:text-amber-400">
            {" "}
            · might already be fixed in {LATEST_VERSION}
          </span>
        ) : null}
      </summary>
      <ReportContextFacts context={context} className="mt-1.5" />
      {open ? children : null}
    </details>
  );
}
