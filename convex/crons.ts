import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "clear expired account deletion markers",
  { hours: 1 },
  internal.sync.clearExpiredAccountDeletionMarkers,
  {},
);

export default crons;
