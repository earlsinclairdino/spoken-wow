/**
 * The note an /r/ page puts above its player: the game plays the clip its pack shipped with,
 * and this page plays the live take, which may be a fix made since. Without it a player
 * reports what they heard in the game without checking, and triage spends a listen on a
 * problem that is already gone.
 */
import { cn } from "@/lib/utils";
import { TriangleAlertIcon } from "lucide-react";

export default function ListenFirst({ className }: { className?: string }) {
  return (
    <aside
      role="note"
      className={cn(
        "flex gap-3 rounded-md border border-amber-500/50 bg-amber-500/10 p-3 text-sm",
        className,
      )}
    >
      <TriangleAlertIcon className="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400" />
      <div>
        <p className="font-medium text-amber-700 dark:text-amber-300">Important: listen first</p>
        <p className="mt-1">
          This line may have changed since your pack. Play the current version below before
          reporting.
        </p>
      </div>
    </aside>
  );
}
