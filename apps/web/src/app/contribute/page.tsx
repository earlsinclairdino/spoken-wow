import type { Metadata } from "next";
import { headers } from "next/headers";

import ContributeForm from "@/components/ContributeForm";
import { auth } from "@/lib/auth";

/**
 * Where the addons send a player when there is no audio for a quest, book page or place.
 *
 * The address the copy box's frame names -- spoken.rusty.one/contribute -- so it has to work
 * with nothing but what the player pasted: most of the people who reach it have no account
 * here, and never will.
 *
 * The session is read only to decide whether to ASK for a name. Someone signed in has already
 * answered that question, and the route takes their identity from the session regardless of
 * what the form sends, so showing them the fields would be offering a choice that does not
 * exist. Reading it is also why this page cannot be static.
 */
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Contribute · Spoken",
  description: "Paste the game's own text for something Spoken has no narration for yet.",
};

export default async function Page() {
  const session = await auth.api.getSession({ headers: await headers() });
  // The name if they have one, the email otherwise: better to say "Filed as you@example.com"
  // than "Filed as ." for an account that never set a display name.
  const signedInAs = session ? (session.user.name?.trim() || session.user.email) : null;

  return (
    <main className="mx-auto max-w-6xl px-5 pt-8 pb-24">
      <article className="max-w-xl">
        <h1 className="text-xl font-semibold">Contribute</h1>
        <p className="text-muted-foreground mt-1 mb-6 text-sm">
          Paste the text an addon gave you for something Spoken has not narrated yet. A person
          reads the queue, not a script, so it can take a while before it is answered.
        </p>

        <ContributeForm signedInAs={signedInAs} />
      </article>
    </main>
  );
}
