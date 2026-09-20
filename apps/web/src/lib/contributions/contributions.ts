/**
 * What a contribution is, in terms both the server and the browser can hold.
 *
 * Free of node imports on purpose, as lib/reports/reports.ts is: the paste form is a client
 * component and needs COMPLAINT_MAX, and importing anything that reaches for node would drag it
 * into the browser bundle. The hashing that submissionFrom needs lives in submission.ts for
 * exactly that reason.
 */
import type { EnvelopeSource } from "./envelope";

export const STATUSES = ["new", "accepted", "rejected"] as const;
export type ContributionStatus = (typeof STATUSES)[number];

export function isStatus(value: unknown): value is ContributionStatus {
  return typeof value === "string" && (STATUSES as readonly string[]).includes(value);
}

/** The same cap the reports body carries, for the same reason. */
export const COMPLAINT_MAX = 4000;

export type Submission = {
  source: EnvelopeSource;
  key: string;
  locale: string;
  build: string;
  text: string | null;
  meta: Record<string, string>;
  raw: string;
  dedup: string;
};
