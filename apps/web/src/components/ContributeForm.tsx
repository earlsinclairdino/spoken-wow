"use client";

/**
 * The form a player pastes an envelope into.
 *
 * THE PREVIEW IS THE POINT. The payload is text out of their own client and they cannot read
 * it in the box -- it is a wall of key=value lines -- so the parse is rendered field by field
 * above the Send button. Nobody should be asked to send something they cannot read.
 *
 * The parse runs here rather than on submit for the same reason a bad paste is explained in
 * the reader's terms: half a copied envelope is the commonest failure this page will see, and
 * "you pasted half of it" is help, while "checksum" is a diagnosis in a language they do not
 * speak.
 */
import { useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import { checkEnvelope, COMPLAINT_MAX } from "@/lib/contributions/contributions";
import { decodeFragment, type DecodeError, parseEnvelope, type ParseError } from "@/lib/contributions/envelope";

const FIELD_LABELS: Record<string, string> = {
  quest: "Quest",
  event: "Moment",
  npc: "Character",
  title: "Title",
  book: "Book",
  number: "Page",
  page: "Page id",
  map: "Map",
  zone: "Zone",
  subzone: "Place",
  locale: "Language",
  build: "Client",
  addon: "Addon",
  x: "x",
  y: "y",
};

const MESSAGES: Record<ParseError, string> = {
  truncated: "That looks like part of a copy. Select the whole box in the game and copy again.",
  checksum: "That text was changed after it was copied. Copy it again without editing it.",
  version: "That came from a newer addon than this page knows. Update the site's addons, or tell me.",
  source: "That is not something this page can take.",
  oversize: "That is far larger than anything the addon produces.",
  malformed: "That is not an addon's text. Copy the whole box in the game, starting at !SPOKEN.",
};

const LINK_MESSAGES: Record<DecodeError, string> = {
  malformed: "That link is missing its payload. Paste the addon's text into the box below instead.",
  corrupt: "That link looks broken -- copy it again, or paste the addon's text into the box below.",
  // DecompressionStream is missing on pre-16.4 Safari: said plainly, rather than leaving the
  // player looking at a form that silently never fills in.
  unsupported:
    "This browser can't open this kind of link. Paste the addon's text into the box below instead.",
};

export type Preview =
  | { ok: true; rows: { label: string; value: string }[]; text: string | null }
  | { ok: false; message: string };

/** Exported for its test: what the page will show for a given paste. */
export function previewOf(raw: string): Preview {
  if (!raw.trim()) return { ok: false, message: "" };

  const parsed = parseEnvelope(raw);
  if (!parsed.ok) return { ok: false, message: MESSAGES[parsed.error] };

  // A clean parse is not a sendable envelope: submissionFrom (via checkEnvelope) still applies
  // the key/text rules, and previously nothing here did -- a parse-only preview approved
  // things the server would 400 on and told the player nothing about why.
  const check = checkEnvelope(parsed.value);
  if (!check.ok) return { ok: false, message: check.message };

  const rows = Object.entries(parsed.value.fields).map(([key, value]) => ({
    label: FIELD_LABELS[key] ?? key,
    value,
  }));
  return { ok: true, rows, text: parsed.value.text };
}

export default function ContributeForm() {
  const [raw, setRaw] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [linkError, setLinkError] = useState<string | null>(null);

  // The one-copy flow: a #e1= link fills the box itself, so pressing Send is the only thing
  // left for the player to do. Runs once, client-side only -- window.location.hash never
  // exists during the server render, and the hash is stripped from the address bar immediately
  // rather than merely read, so it cannot linger in history or get shared onward carrying the
  // decoded game text a second time.
  useEffect(() => {
    const hash = window.location.hash;
    if (!hash.startsWith("#e1=")) return;

    window.history.replaceState(null, "", window.location.pathname + window.location.search);

    let cancelled = false;
    decodeFragment(hash.slice("#e1=".length)).then((result) => {
      if (cancelled) return;
      if (result.ok) {
        setRaw(result.text);
      } else {
        setLinkError(LINK_MESSAGES[result.error]);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const preview = previewOf(raw);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const data = new FormData(event.currentTarget);
    const response = await fetch("/api/contributions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        envelope: raw,
        body: data.get("body"),
        name: data.get("name"),
        email: data.get("email"),
        website: data.get("website"),
      }),
    }).catch(() => null);

    setBusy(false);
    if (response?.ok) {
      setSent(true);
    } else {
      setError("That did not go through. Try again in a minute.");
    }
  }

  if (sent) {
    // The same reasoning as ReportForm's success screen: the sender cannot read their
    // submission back, so a form that merely cleared itself would leave them with no evidence.
    return (
      <p role="status" className="rounded border p-4 text-sm">
        Got it — thank you. It is in the queue with everything else players have sent.
      </p>
    );
  }

  return (
    <form onSubmit={submit} className="flex max-w-xl flex-col gap-4">
      {linkError ? (
        <p role="alert" className="text-sm text-red-400">
          {linkError}
        </p>
      ) : null}

      <label className="flex flex-col gap-1 text-sm">
        Paste what the addon gave you
        <textarea
          id="envelope"
          rows={10}
          value={raw}
          onChange={(e) => setRaw(e.target.value)}
          required
          className="bg-background rounded border px-2 py-1.5 font-mono text-xs"
        />
      </label>

      {!preview.ok && preview.message ? (
        <p role="alert" className="text-sm text-red-400">
          {preview.message}
        </p>
      ) : null}

      {preview.ok ? (
        <section aria-label="What will be sent" className="bg-muted rounded border p-3 text-sm">
          <ul className="flex flex-col gap-0.5">
            {preview.rows.map((row) => (
              <li key={row.label}>
                <strong>{row.label}:</strong> {row.value}
              </li>
            ))}
          </ul>
          {preview.text ? <pre className="mt-2 whitespace-pre-wrap">{preview.text}</pre> : null}
        </section>
      ) : null}

      <label className="flex flex-col gap-1 text-sm">
        Anything to add? (optional)
        <textarea
          name="body"
          maxLength={COMPLAINT_MAX}
          rows={3}
          className="bg-background rounded border px-2 py-1.5"
        />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Your name (optional)
        <input name="name" className="bg-background rounded border px-2 py-1.5" />
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Your email (optional)
        <input name="email" type="email" className="bg-background rounded border px-2 py-1.5" />
      </label>

      {/* A honeypot. sr-only rather than display:none, which bots know to skip. */}
      <label className="sr-only" aria-hidden="true">
        Website
        <input name="website" tabIndex={-1} autoComplete="off" />
      </label>

      {error ? (
        <p role="alert" className="text-sm text-red-400">
          {error}
        </p>
      ) : null}

      <div>
        <Button type="submit" disabled={busy || !preview.ok}>
          {busy ? "Sending…" : "Send it"}
        </Button>
      </div>
    </form>
  );
}
