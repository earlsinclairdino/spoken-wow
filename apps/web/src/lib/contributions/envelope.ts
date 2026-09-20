/**
 * The reader for the envelope addons/SpokenPlayer/Contribute.lua writes.
 *
 * THE TWO MUST AGREE EXACTLY, and the fixtures under tests/fixtures/contributions are what
 * holds them together -- the Lua writes them, this reads them, and a format change that
 * touches only one side fails in the commit that makes it. The same arrangement, and the same
 * reason, as SpokenBooks/Checksum.lua and pipelines/books/tools/lib/naming.mjs.
 *
 * Free of node imports: the paste box is a client component and previews the parse before
 * anything is sent.
 */

/** Large enough for a long quest, small enough that a pasted log is refused rather than stored. */
export const MAX_BYTES = 64 * 1024;

const SOURCES = ["quests", "zones", "books"] as const;
export type EnvelopeSource = (typeof SOURCES)[number];

export type Envelope = {
  source: EnvelopeSource;
  fields: Record<string, string>;
  text: string | null;
};

export type ParseError = "version" | "source" | "checksum" | "truncated" | "oversize" | "malformed";

type Result = { ok: true; value: Envelope } | { ok: false; error: ParseError };

const MODULUS = 2147483647;
const FACTOR = 31;

/**
 * The Lua writer's checksum, over bytes rather than characters.
 *
 * TextEncoder, not charCodeAt: string.byte on the client walks UTF-8 bytes, so a Cyrillic
 * quest -- the exact case this feature exists for -- would differ on every character otherwise.
 */
export function checksum(body: string): number {
  const bytes = new TextEncoder().encode(body);
  let sum = bytes.length % MODULUS;
  for (const b of bytes) {
    sum = (sum * FACTOR + b) % MODULUS;
  }
  return sum;
}

export function parseEnvelope(raw: string): Result {
  if (new TextEncoder().encode(raw).length > MAX_BYTES) {
    return { ok: false, error: "oversize" };
  }

  // A paste picks up blank lines and \r\n at both ends and neither is the player's fault.
  const normalised = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim() + "\n";

  const closed = normalised.match(/^([\s\S]*\n)sum=(\d+)\n$/);
  if (!closed) return { ok: false, error: "truncated" };
  const [, body, sum] = closed;

  const lines = body.split("\n");
  const header = lines.shift() ?? "";
  const headerMatch = header.match(/^!SPOKEN(\d+) (\S+)$/);
  if (!headerMatch) return { ok: false, error: "malformed" };
  if (headerMatch[1] !== "1") return { ok: false, error: "version" };

  const source = headerMatch[2] as EnvelopeSource;
  if (!SOURCES.includes(source)) return { ok: false, error: "source" };

  // The checksum is verified before the body is trusted, but after the header: a 2.x envelope
  // should say so rather than reporting a checksum failure at someone who pasted correctly.
  if (checksum(body) !== Number(sum)) return { ok: false, error: "checksum" };

  const fields: Record<string, string> = {};
  let text: string | null = null;

  while (lines.length) {
    const line = lines.shift()!;
    if (line === "") continue;

    if (line === "text<<") {
      const collected: string[] = [];
      let closedFence = false;
      while (lines.length) {
        const inner = lines.shift()!;
        if (inner === ">>") {
          closedFence = true;
          break;
        }
        // One backslash off a line the writer escaped, so a page whose own words are ">>"
        // survives the round trip.
        collected.push(/^\\+>>$/.test(inner) ? inner.slice(1) : inner);
      }
      if (!closedFence) return { ok: false, error: "truncated" };
      text = collected.join("\n");
      continue;
    }

    const split = line.indexOf("=");
    if (split <= 0) return { ok: false, error: "malformed" };
    fields[line.slice(0, split)] = line.slice(split + 1);
  }

  return { ok: true, value: { source, fields, text } };
}
