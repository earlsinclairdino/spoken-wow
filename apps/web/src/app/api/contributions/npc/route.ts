/**
 * A moderator's answer about who is speaking.
 *
 * A sibling of the public POST rather than a verb on it, for the reason
 * api/reports/resolve/route.ts gives: that path is open to the whole internet and this one must
 * never be. Collaborator, matching /resolve.
 *
 * Writes through to the NPC rather than the contribution, so one correction fixes every line
 * that NPC speaks -- which is the point of keying the table the way it is keyed.
 *
 * Always writes "moderator"/confirmed, even when a moderator clears race, gender and flavor
 * back to null. That is a real answer, not an empty one -- "this NPC has no race" is the same
 * normal outcome resolve.ts's own docstring describes for a corpus miss -- and it must stay
 * ranked "moderator" so a lower-ranked client guess can never silently overwrite a human's
 * considered "nothing here". Neither invariant in migration 0031 objects: the "none is empty"
 * check only constrains provenance "none", and the "confirmed implies corpus or moderator"
 * check is satisfied by "moderator" whether or not the row is confirmed.
 */
import { requireRegenerate } from "@/lib/generation/authz";
import { getResolution, NPC_KINDS, upsertResolution, type NpcKind } from "@/lib/npc/store";

export const dynamic = "force-dynamic";

// An integer column (migration 0030), same as the intake path's npcId -- see resolve.ts's
// digits() for why an upper bound matters here too: a moderator's own POST is authenticated,
// but nothing stops a mistyped or pasted id from being just as oversized, and the same
// out-of-range insert would fail the same way.
const INT32_MAX = 2147483647;

export async function POST(request: Request) {
  const { session, denied } = await requireRegenerate();
  if (denied) return denied;

  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;

  const npcKind = (NPC_KINDS as readonly string[]).includes(body.npcKind as string)
    ? (body.npcKind as NpcKind)
    : null;
  const npcId = Number(body.npcId);
  if (!npcKind) return Response.json({ error: "unknown kind" }, { status: 400 });
  // `< 0`, not `<= 0`: id 0 is a real NPC id (resolve.ts's own observedFrom/resolveNpc treat it
  // that way, with an explicit "not a truthiness check" note), and a moderator must be able to
  // correct it exactly like any other id the intake path resolved automatically.
  if (!Number.isInteger(npcId) || npcId < 0 || npcId > INT32_MAX) {
    return Response.json({ error: "unknown npc" }, { status: 400 });
  }

  const text = (value: unknown, max: number) =>
    typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;

  // What the client reported is kept even when a moderator overrules it: it is evidence about
  // the NPC, and the next person to look may want to know what the guess was based on.
  const existing = await getResolution(npcKind, npcId);

  const row = await upsertResolution({
    npcKind,
    npcId,
    npcName: existing?.npcName ?? null,
    race: text(body.race, 64),
    gender: text(body.gender, 16),
    flavor: text(body.flavor, 64),
    provenance: "moderator",
    confirmed: true,
    modelFileId: existing?.modelFileId ?? null,
    sex: existing?.sex ?? null,
    creatureType: existing?.creatureType ?? null,
    build: existing?.build ?? null,
    note: text(body.note, 2000),
    resolvedBy: session.user.id,
  });

  return Response.json({ resolution: row });
}
