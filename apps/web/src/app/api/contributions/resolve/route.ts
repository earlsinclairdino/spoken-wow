/**
 * Changing a contribution's status.
 *
 * A sibling route, not a second verb on /api/contributions: that path's POST is open to the
 * whole internet and this one must never be. Collaborator rather than admin, as on the reports
 * side -- these are the people who already act on lines.
 */
import { requireRegenerate } from "@/lib/generation/authz";
import { isStatus } from "@/lib/contributions/contributions";
import { setContributionStatus } from "@/lib/contributions/store";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const { session, denied } = await requireRegenerate();
  if (denied) return denied;

  const body = (await request.json().catch(() => ({}))) as { id?: unknown; status?: unknown };

  const id = Number(body.id);
  if (!Number.isInteger(id) || id <= 0) {
    return Response.json({ error: "unknown contribution" }, { status: 404 });
  }
  if (!isStatus(body.status)) {
    return Response.json({ error: "unknown status" }, { status: 400 });
  }

  const contribution = await setContributionStatus(id, body.status, session.user.id);
  if (!contribution) {
    return Response.json({ error: "unknown contribution" }, { status: 404 });
  }

  return Response.json({ contribution });
}
