/**
 * What the pipelines read.
 *
 * NDJSON rather than a write into a staging table, because there is no staging table to write
 * into: the quests corpus is built in pipelines/quests against vmangos, not in this database,
 * and the books corpus is built from the same world DB. A file the pipeline pulls is the
 * boundary those two already have.
 *
 * Collaborator-only, like /resolve: accepted text is still text somebody typed into a public
 * form, and the queue it came from is not public reading.
 */
import { requireRegenerate } from "@/lib/generation/authz";
import { acceptedContributions } from "@/lib/contributions/store";

export const dynamic = "force-dynamic";

export async function GET() {
  const { denied } = await requireRegenerate();
  if (denied) return denied;

  const rows = await acceptedContributions();
  const body = rows
    .map((row) =>
      JSON.stringify({
        id: row.id,
        source: row.source,
        key: row.key,
        locale: row.locale,
        build: row.build,
        text: row.text,
        meta: row.meta,
        count: row.count,
      }),
    )
    .join("\n");

  return new Response(body ? body + "\n" : "", {
    headers: { "content-type": "application/x-ndjson; charset=utf-8" },
  });
}
