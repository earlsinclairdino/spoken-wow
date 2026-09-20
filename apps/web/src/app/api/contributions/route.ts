/**
 * Sending text this corpus does not have.
 *
 * THIS IS THE SECOND UNAUTHENTICATED WRITE IN THIS APP, and it exists for the reason the first
 * one does: the person best placed to send a missing quest is the player standing in front of
 * the NPC, and they have no account here. Every defence below is because of that, and any verb
 * added to this path inherits the exposure -- put it in a sibling route, as /resolve is for
 * reports.
 *
 * A contribution never becomes a regeneration job, for the reason api/reports/route.ts gives:
 * a public write that could start one would be a public write that spends money. A
 * collaborator reads the row and the pipeline picks it up from the export.
 */
import { headers } from "next/headers";

import { auth } from "@/lib/auth";
import { clientIp } from "@/lib/reports/client-ip";
import { COMPLAINT_MAX } from "@/lib/contributions/contributions";
import { MAX_BYTES, parseEnvelope } from "@/lib/contributions/envelope";
import { submissionFrom } from "@/lib/contributions/submission";
import {
  countRecentContributions,
  createContribution,
  recordContributionHit,
} from "@/lib/contributions/store";

export const dynamic = "force-dynamic";

/** Deliberately not configurable, as the reports limit is not: a knob nobody turns is set wrong. */
const PER_HOUR = 10;
const WINDOW_MS = 60 * 60 * 1000;

export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;

  // 200 and not 400, as on the reports route: a bot that believes it succeeded stops adapting.
  if (typeof body.website === "string" && body.website.trim()) {
    return Response.json({ ok: true });
  }

  const raw = typeof body.envelope === "string" ? body.envelope : "";
  // Checked before parsing, not inside it: the cap exists so a pasted log is refused rather
  // than walked.
  if (new TextEncoder().encode(raw).length > MAX_BYTES) {
    return Response.json({ error: "oversize" }, { status: 413 });
  }

  const parsed = parseEnvelope(raw);
  if (!parsed.ok) {
    return Response.json({ error: parsed.error }, { status: 400 });
  }

  const submission = submissionFrom(parsed.value, raw);
  if (!submission) {
    return Response.json({ error: "incomplete" }, { status: 400 });
  }

  const complaint = typeof body.body === "string" ? body.body.trim().slice(0, COMPLAINT_MAX) : "";

  const ip = clientIp(request);
  if ((await countRecentContributions(ip, WINDOW_MS)) >= PER_HOUR) {
    return Response.json({ error: "too many contributions" }, { status: 429 });
  }

  // Identity from the session when there is one, and the typed fields dropped rather than
  // merged -- the reports route's reasoning: signing in and typing someone else's name is a
  // way to put words in their mouth.
  const session = await auth.api.getSession({ headers: await headers() });

  await createContribution({
    ...submission,
    body: complaint || null,
    userId: session?.user.id ?? null,
    name: session ? null : stringOrNull(body.name, 200),
    email: session ? null : stringOrNull(body.email, 320),
    ip,
  });

  // After the write, and unconditionally: the hit is what the limiter counts, and an identical
  // paste that only bumped a count is still a paste.
  await recordContributionHit(ip);

  return Response.json({ ok: true });
}

function stringOrNull(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, max) : null;
}
