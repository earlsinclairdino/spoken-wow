import type { Metadata } from "next";

import ContributeForm from "@/components/ContributeForm";

/**
 * Where the addons send a player when there is no audio for a quest, book page or place.
 *
 * The address the copy box's frame names -- spoken.rusty.one/contribute -- so it has to work
 * with nothing but what the player pasted: no session, no lookup, no way to identify who they
 * are beyond what they choose to add.
 */
export const metadata: Metadata = {
  title: "Contribute · Spoken",
  description: "Paste the game's own text for something Spoken has no narration for yet.",
};

export default function Page() {
  return (
    <main className="mx-auto max-w-6xl px-5 pt-8 pb-24">
      <article className="max-w-xl">
        <h1 className="text-xl font-semibold">Contribute</h1>
        <p className="text-muted-foreground mt-1 mb-6 text-sm">
          Paste the text an addon gave you for something Spoken has not narrated yet. A person
          reads the queue, not a script, so it can take a while before it is answered.
        </p>

        <ContributeForm />
      </article>
    </main>
  );
}
