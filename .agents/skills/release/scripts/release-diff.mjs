#!/usr/bin/env node

import { execFileSync } from "node:child_process";

const git = (...args) => execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();

const from = process.argv[2] ?? git("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", "origin/main");
const to = process.argv[3] ?? "origin/main";
const range = `${from}..${to}`;

const records = git("log", "--first-parent", "--format=%H%x1f%s%x1f%b%x1e", range)
  .split("\x1e")
  .map((r) => r.trim())
  .filter(Boolean);
const prs = [];
const direct = [];
for (const record of records) {
  const [sha, subject, body = ""] = record.split("\x1f");
  const merge = subject.match(/^Merge pull request #(\d+) from (\S+)/);
  const squash = subject.match(/\(#(\d+)\)$/);
  if (merge) {
    const title = body.split("\n").map((l) => l.trim()).find(Boolean) ?? merge[2];
    prs.push({ number: merge[1], title, sha });
  } else if (squash) {
    prs.push({ number: squash[1], title: subject.replace(/\s*\(#\d+\)$/, ""), sha });
  } else {
    direct.push({ sha, subject });
  }
}

// --no-renames lists a moved file at both its old and new path, so the path-based signals below still see it.
const numstat = git("diff", "--numstat", "--no-renames", range)
  .split("\n")
  .filter(Boolean)
  .map((l) => {
    const [added, removed, path] = l.split("\t");
    return { path, churn: (Number(added) || 0) + (Number(removed) || 0) };
  });

function area(path) {
  const parts = path.split("/");
  if (parts[0] === "Baros" && ["Features", "Core"].includes(parts[1]) && parts.length > 3) {
    return parts.slice(0, 3).join("/");
  }
  if (parts[0] === "BarosCore" && parts[1] === "Sources" && parts[3] === "Features" && parts.length > 5) {
    return parts.slice(0, 5).join("/");
  }
  if (parts[0] === "BarosCore" && parts[1] === "Sources" && parts.length > 4) {
    return parts.slice(0, 4).join("/");
  }
  if (["Baros", "convex", "docs", "SupportSite"].includes(parts[0]) && parts.length > 2) {
    return parts.slice(0, 2).join("/");
  }
  return parts.length > 1 ? parts[0] : "(root)";
}

const areas = new Map();
for (const f of numstat) {
  const key = area(f.path);
  const entry = areas.get(key) ?? { files: 0, churn: 0 };
  entry.files += 1;
  entry.churn += f.churn;
  areas.set(key, entry);
}

const paths = numstat.map((f) => f.path);
const touched = (re) => paths.filter((p) => re.test(p));
const projectYmlChanges = git("diff", "-U0", range, "--", "project.yml")
  .split("\n")
  .filter((l) => /^[+-](?![+-])/.test(l) && !/MARKETING_VERSION|CURRENT_PROJECT_VERSION/.test(l));
const signals = {
  "Device check (signing, entitlements, capabilities, privacy manifest)": [
    ...touched(/\.entitlements$|Info\.plist$|PrivacyInfo\.xcprivacy$/),
    ...(projectYmlChanges.length ? [`project.yml (${projectYmlChanges.length} non-version lines)`] : []),
  ],
  // A new @Model must be registered in Persistence/BarosSchema.swift, so only the existing ones outside Models/ need naming.
  "Upgrade test (persisted model or schema)": touched(
    /^Baros\/Core\/Persistence\/|^Baros\/(Core\/)?Models?\/|^BarosCore\/Sources\/BarosCore\/(Persistence|Models)\/|^BarosCore\/Sources\/BarosCore\/Sync\/Sync(OutboxEntry|CursorState)\.swift$/,
  ).filter((p) => !p.includes("UITestFixture")),
  "Dependencies (Swift packages)": touched(/Package\.resolved$/),
  "Backend contract (Convex schema/functions)": touched(/^convex\/(?!_generated\/).*\.ts$/).filter((p) => !p.includes(".test.")),
};

console.log(`Range: ${range} (${records.length} first-parent commits, ${numstat.length} files changed)\n`);
console.log(`Merged PRs (${prs.length}):`);
for (const pr of prs) console.log(`  #${pr.number}  ${pr.title}`);
if (direct.length) {
  console.log(`\nDirect commits on main (${direct.length}):`);
  for (const c of direct) console.log(`  ${c.sha.slice(0, 8)}  ${c.subject}`);
}
console.log("\nChanged areas (by churn):");
for (const [key, v] of [...areas].sort((a, b) => b[1].churn - a[1].churn)) {
  console.log(`  ${String(v.churn).padStart(6)}  ${String(v.files).padStart(3)} files  ${key}`);
}
console.log("\nSignals:");
for (const [label, hits] of Object.entries(signals)) {
  console.log(`  ${hits.length ? "YES" : "no "}  ${label}`);
  for (const h of hits.slice(0, 12)) console.log(`         ${h}`);
  if (hits.length > 12) console.log(`         ... ${hits.length - 12} more`);
}
