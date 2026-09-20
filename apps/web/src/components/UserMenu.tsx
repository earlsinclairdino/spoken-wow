"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { signOut, useSession } from "@/lib/auth-client";
import { canConfigureGeneration, canManageVoices, canRegenerate, isAdmin } from "@/lib/permissions";

/**
 * The session indicator in the header.
 *
 * It reads the session in the browser rather than through a server component on purpose:
 * an RSC session read in the root layout would opt every page into dynamic rendering and
 * put a database round trip in front of every page view of a tool that is otherwise served
 * entirely off disk.
 */
export default function UserMenu() {
  const router = useRouter();
  const { data: session, isPending } = useSession();

  // Rendering nothing until the session resolves avoids a "Sign in" flash for a user who
  // is in fact signed in.
  if (isPending) return null;

  if (!session) {
    return (
      <nav className="flex items-center gap-1">
        <Button asChild variant="ghost" size="sm">
          <Link href="/quests">Quests</Link>
        </Button>
        <Button asChild variant="ghost" size="sm">
          <Link href="/zones">Zones</Link>
        </Button>
        <Button asChild variant="ghost" size="sm">
          <Link href="/books">Books</Link>
        </Button>
        <Button asChild variant="ghost" size="sm">
          <Link href="/login">Sign in</Link>
        </Button>
        <Button asChild variant="outline" size="sm">
          <Link href="/register">Register</Link>
        </Button>
      </nav>
    );
  }

  const role = session.user.role;

  return (
    <nav className="flex items-center gap-2">
      {/* The three sections, for everyone: they are what the site is, and a visitor who
          landed on one should be able to find the others without going back to the door. */}
      <Button asChild variant="ghost" size="sm">
        <Link href="/quests">Quests</Link>
      </Button>
      <Button asChild variant="ghost" size="sm">
        <Link href="/zones">Zones</Link>
      </Button>
      <Button asChild variant="ghost" size="sm">
        <Link href="/books">Books</Link>
      </Button>
      {canManageVoices(role) && (
        <Button asChild variant="ghost" size="sm">
          <Link href="/voices">Voices</Link>
        </Button>
      )}
      {canConfigureGeneration(role) && (
        <Button asChild variant="ghost" size="sm">
          <Link href="/lexicon">Pronunciation</Link>
        </Button>
      )}
      {canConfigureGeneration(role) && (
        <Button asChild variant="ghost" size="sm">
          <Link href="/issues">Issues</Link>
        </Button>
      )}
      {canRegenerate(role) && (
        <Button asChild variant="ghost" size="sm">
          <Link href="/reports">Reports</Link>
        </Button>
      )}
      {canRegenerate(role) && (
        <Button asChild variant="ghost" size="sm">
          <Link href="/contributions">Contributions</Link>
        </Button>
      )}
      {isAdmin(role) && (
        <Button asChild variant="ghost" size="sm">
          <Link href="/admin">Users</Link>
        </Button>
      )}
      {/* Everyone signed in has one, and for a collaborator it is where the ElevenLabs
          key lives - which is the thing standing between them and the Regenerate button. */}
      <Button asChild variant="ghost" size="sm">
        <Link href="/profile">Profile</Link>
      </Button>
      <span className="text-muted-foreground hidden text-xs sm:inline">
        {session.user.email}
      </span>
      <Badge variant="outline" className="uppercase">
        {role ?? "member"}
      </Badge>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => signOut().then(() => router.refresh())}
      >
        Sign out
      </Button>
    </nav>
  );
}
