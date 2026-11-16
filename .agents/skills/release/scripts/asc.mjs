#!/usr/bin/env node
// App Store Connect client for the release skill.
//
// Credentials: ~/.appstoreconnect/release.env with ASC_KEY_ID, ASC_ISSUER_ID and
// ASC_KEY_PATH (a Team key with the App Manager role). Node built-ins only.
//
// Reads run immediately. Write commands (prepare, submit, release) print the
// requests they would send and send them only with --apply.
//
//   node asc.mjs check
//   node asc.mjs runs [--build <number>] [--commit <sha>] [--branch <name>] [--limit <n>]
//   node asc.mjs versions [--limit <n>]
//   node asc.mjs status <version>
//   node asc.mjs prepare <version> --build <number> --whats-new <file> [--apply]
//   node asc.mjs submit <version> [--apply]
//   node asc.mjs release <version> [--apply]
//   node asc.mjs listing <version> [--screenshots <dir>] [--apply]

import { readFileSync, readdirSync, statSync } from "node:fs";
import { createHash, createSign } from "node:crypto";
import { homedir } from "node:os";
import { execFileSync } from "node:child_process";

const BUNDLE_ID = "com.kevintatooles.LiftingLog";
const LOCALE = "en-US";
const API = "https://api.appstoreconnect.apple.com";
// The 6.9" iPhone slot; App Store Connect scales it for every smaller iPhone.
const SCREENSHOT_DISPLAY_TYPE = "APP_IPHONE_67";
const LISTING_PATH = new URL("../../../../docs/release/listing.json", import.meta.url);
// MD5 of each approved App Store image, written by `pnpm -C SupportSite listing-assets`.
const APPROVED_LISTING_PATH = new URL("../../../../docs/release/listing-approved.json", import.meta.url);
const SCREENSHOT_SLOT_LIMIT = 10;
// States in which the version's build, release type and notes can still change.
const EDITABLE = new Set([
  "PREPARE_FOR_SUBMISSION",
  "READY_FOR_REVIEW",
  "DEVELOPER_REJECTED",
  "REJECTED",
  "METADATA_REJECTED",
  "INVALID_BINARY",
]);

// ---------- auth and transport ----------

function loadEnv() {
  const path = `${homedir()}/.appstoreconnect/release.env`;
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    fail(`Missing ${path}; it needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see the release skill's SKILL.md).`);
  }
  const env = {};
  for (const line of text.split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^"|"$/g, "");
  }
  for (const key of ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"]) {
    if (!env[key]) fail(`${path} is missing ${key}.`);
  }
  return env;
}

let cachedToken;
function token() {
  if (cachedToken) return cachedToken;
  const env = loadEnv();
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const input = `${b64({ alg: "ES256", kid: env.ASC_KEY_ID, typ: "JWT" })}.${b64({
    iss: env.ASC_ISSUER_ID,
    iat: now,
    exp: now + 1200,
    aud: "appstoreconnect-v1",
  })}`;
  const signature = createSign("SHA256")
    .update(input)
    .sign({ key: readFileSync(env.ASC_KEY_PATH), dsaEncoding: "ieee-p1363" })
    .toString("base64url");
  cachedToken = `${input}.${signature}`;
  return cachedToken;
}

async function api(method, path, body) {
  const res = await fetch(API + path, {
    method,
    headers: {
      Authorization: `Bearer ${token()}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const detail = (json.errors ?? [])
      .map((e) => `${e.status} ${e.code}: ${e.detail ?? e.title}`)
      .join("\n  ");
    fail(`${method} ${path} -> HTTP ${res.status}\n  ${detail || "no error body"}`);
  }
  return json;
}

const get = (path) => api("GET", path);

// ---------- lookups ----------

async function appId() {
  const { data } = await get(`/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=name`);
  if (!data.length) fail(`No app with bundle ID ${BUNDLE_ID} is visible to this key.`);
  return data[0].id;
}

async function findVersion(app, versionString) {
  const { data } = await get(
    `/v1/apps/${app}/appStoreVersions?filter[versionString]=${versionString}&filter[platform]=IOS`,
  );
  return data[0] ?? null;
}

async function versionBuild(versionId) {
  const { data } = await get(
    `/v1/appStoreVersions/${versionId}/build?fields[builds]=version,processingState,expired`,
  );
  return data ?? null;
}

async function localization(versionId) {
  const { data } = await get(
    `/v1/appStoreVersions/${versionId}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,whatsNew`,
  );
  return data.find((l) => l.attributes.locale === LOCALE) ?? null;
}

async function findBuild(app, versionString, number) {
  const { data } = await get(
    `/v1/builds?filter[app]=${app}&filter[version]=${number}&filter[preReleaseVersion.version]=${versionString}` +
      `&fields[builds]=version,processingState,expired`,
  );
  return data[0] ?? null;
}

async function submissions(app) {
  const { data } = await get(
    `/v1/reviewSubmissions?filter[app]=${app}&filter[platform]=IOS&limit=10`,
  );
  return data;
}

async function submissionItems(submissionId) {
  const { data } = await get(
    `/v1/reviewSubmissions/${submissionId}/items?include=appStoreVersion&fields[reviewSubmissionItems]=state,appStoreVersion`,
  );
  return data;
}

// ---------- commands ----------

async function check() {
  const { data } = await get(`/v1/apps?filter[bundleId]=${BUNDLE_ID}&fields[apps]=name,bundleId`);
  if (!data.length) fail(`Key works, but no app with bundle ID ${BUNDLE_ID} is visible.`);
  console.log(`OK: ${data[0].attributes.name} (${data[0].attributes.bundleId}, app ${data[0].id})`);
}

async function runs(opts) {
  const app = await appId();
  const { data: product } = await get(`/v1/apps/${app}/ciProduct`);
  const searching = Boolean(opts.commit || opts.build || opts.branch);
  const limit = Number(opts.limit ?? (searching ? 100 : 10));
  const { data, included = [] } = await get(
    `/v1/ciProducts/${product.id}/buildRuns?sort=-number&limit=${Math.min(limit, 200)}` +
      "&include=sourceBranchOrTag,workflow&fields[scmGitReferences]=name&fields[ciWorkflows]=name",
  );
  const names = new Map(included.map((i) => [`${i.type}/${i.id}`, i.attributes?.name]));
  const nameOf = (rel) => (rel?.data ? names.get(`${rel.data.type}/${rel.data.id}`) : undefined);

  let shown = 0;
  for (const run of data) {
    const a = run.attributes;
    const branch = nameOf(run.relationships?.sourceBranchOrTag) ?? "?";
    if (opts.commit && !a.sourceCommit?.commitSha?.startsWith(opts.commit)) continue;
    if (opts.branch && branch !== opts.branch) continue;
    const { data: builds } = await get(
      `/v1/ciBuildRuns/${run.id}/builds?fields[builds]=version,processingState,expired`,
    );
    if (opts.build && builds[0]?.attributes.version !== String(opts.build)) continue;
    const build = builds[0]
      ? `build ${builds[0].attributes.version} ${builds[0].attributes.processingState}${builds[0].attributes.expired ? " EXPIRED" : ""}`
      : "no build";
    const title = (a.sourceCommit?.message ?? "").split("\n").filter(Boolean).pop() ?? "";
    console.log(
      [
        `run #${a.number}`,
        `${a.executionProgress}/${a.completionStatus ?? "-"}`,
        build,
        `branch ${branch}`,
        `workflow "${nameOf(run.relationships?.workflow) ?? "?"}"`,
        `commit ${a.sourceCommit?.commitSha ?? "?"}`,
        `run-id ${run.id}`,
        `finished ${a.finishedDate ?? "-"}`,
      ].join("  "),
    );
    if (title) console.log(`    ${title}`);
    shown += 1;
    if (opts.build) break;
  }
  if (!shown) console.log(searching ? `No Xcode Cloud run matched within the newest ${limit} runs.` : "No runs.");
}

// Recent App Store versions, newest first, with their "<version> release" milestone state.
// Closing the milestone is the release's last step, so the active release is the newest
// version whose milestone is still open; when none is, the next release is MARKETING_VERSION.
async function versions(opts) {
  const app = await appId();
  const { data } = await get(
    `/v1/apps/${app}/appStoreVersions?filter[platform]=IOS&limit=${Number(opts.limit ?? 5)}` +
      "&fields[appStoreVersions]=versionString,appStoreState,appVersionState,releaseType,createdDate",
  );
  const milestones = new Map(
    JSON.parse(
      execFileSync("gh", ["api", "repos/Tatooles/baros/milestones?state=all&per_page=100"], { encoding: "utf8" }),
    ).map((m) => [m.title, m.state]),
  );
  const sorted = [...data].sort((a, b) => b.attributes.createdDate.localeCompare(a.attributes.createdDate));
  let active = null;
  for (const v of sorted) {
    const a = v.attributes;
    const milestone = milestones.get(`${a.versionString} release`) ?? "no milestone";
    if (milestone === "open" && !active) active = a.versionString;
    console.log(
      `${a.versionString.padEnd(8)} ${a.appVersionState.padEnd(26)} milestone ${milestone}  created ${a.createdDate}`,
    );
  }
  console.log(active ? `Active release: ${active}` : "No listed version has an open milestone; the next release is MARKETING_VERSION.");
}

async function status(versionString) {
  requireVersion(versionString);
  const app = await appId();
  const version = await findVersion(app, versionString);
  if (!version) {
    console.log(`Version ${versionString}: not created in App Store Connect yet.`);
    return;
  }
  const a = version.attributes;
  const build = await versionBuild(version.id);
  const loc = await localization(version.id);
  console.log(`Version ${versionString} (${version.id})`);
  console.log(`  appStoreState:   ${a.appStoreState}`);
  console.log(`  appVersionState: ${a.appVersionState}`);
  console.log(`  releaseType:     ${a.releaseType}`);
  console.log(
    `  build:           ${build ? `${build.attributes.version} (${build.attributes.processingState})` : "none attached"}`,
  );
  console.log(`  whatsNew (${LOCALE}):`);
  console.log(indent(loc?.attributes.whatsNew ?? "(empty)", 4));

  for (const s of await submissions(app)) {
    const items = await submissionItems(s.id);
    if (items.some((i) => i.relationships?.appStoreVersion?.data?.id === version.id)) {
      console.log(
        `  review submission ${s.id}: ${s.attributes.state}` +
          `${s.attributes.submittedDate ? `, submitted ${s.attributes.submittedDate}` : ""}` +
          `; item ${items.map((i) => i.attributes.state).join(", ")}`,
      );
    }
  }
}

async function prepare(versionString, opts) {
  requireVersion(versionString);
  if (!opts.build) fail("prepare needs --build <number>.");
  if (!opts["whats-new"]) fail("prepare needs --whats-new <file>.");
  const whatsNew = readFileSync(opts["whats-new"], "utf8").trim();
  if (!whatsNew) fail(`${opts["whats-new"]} is empty.`);
  if (whatsNew.length > 4000) fail(`What's New is ${whatsNew.length} characters; the limit is 4000.`);

  const app = await appId();
  const build = await findBuild(app, versionString, opts.build);
  if (!build) fail(`No build ${opts.build} for version ${versionString}.`);
  if (build.attributes.processingState !== "VALID" || build.attributes.expired) {
    fail(`Build ${opts.build} is ${build.attributes.processingState}${build.attributes.expired ? ", expired" : ""}.`);
  }

  const plan = new Plan(opts.apply);
  let version = await findVersion(app, versionString);
  if (version) {
    const { appStoreState, appVersionState } = version.attributes;
    if (!EDITABLE.has(appStoreState) && !EDITABLE.has(appVersionState)) {
      fail(`Version ${versionString} is ${appVersionState} (${appStoreState}); it can no longer be edited.`);
    }
    if (version.attributes.releaseType !== "MANUAL") {
      await plan.send("Set release type to MANUAL", "PATCH", `/v1/appStoreVersions/${version.id}`, {
        data: { type: "appStoreVersions", id: version.id, attributes: { releaseType: "MANUAL" } },
      });
    }
    const current = await versionBuild(version.id);
    if (current?.id !== build.id) {
      await plan.send(
        `Attach build ${opts.build}${current ? ` (replacing ${current.attributes.version})` : ""}`,
        "PATCH",
        `/v1/appStoreVersions/${version.id}/relationships/build`,
        { data: { type: "builds", id: build.id } },
      );
    }
  } else {
    const created = await plan.send(
      `Create version ${versionString} (manual release) with build ${opts.build}`,
      "POST",
      "/v1/appStoreVersions",
      {
        data: {
          type: "appStoreVersions",
          attributes: { platform: "IOS", versionString, releaseType: "MANUAL" },
          relationships: {
            app: { data: { type: "apps", id: app } },
            build: { data: { type: "builds", id: build.id } },
          },
        },
      },
    );
    version = created?.data ?? null;
  }

  const loc = version ? await localization(version.id) : null;
  if (!version) {
    // Dry run of a version that does not exist yet: the localization is resolved after creation.
    await plan.send(`Set ${LOCALE} What's New on the new version`, "PATCH", "/v1/appStoreVersionLocalizations/<new>", null);
  } else if (loc && loc.attributes.whatsNew?.trim() !== whatsNew) {
    await plan.send(`Set ${LOCALE} What's New`, "PATCH", `/v1/appStoreVersionLocalizations/${loc.id}`, {
      data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: { whatsNew } },
    });
  } else if (!loc) {
    await plan.send(`Create ${LOCALE} localization with What's New`, "POST", "/v1/appStoreVersionLocalizations", {
      data: {
        type: "appStoreVersionLocalizations",
        attributes: { locale: LOCALE, whatsNew },
        relationships: {
          appStoreVersion: { data: { type: "appStoreVersions", id: version?.id ?? "<new version>" } },
        },
      },
    });
  }

  plan.finish();
  if (opts.apply) await status(versionString);
}

async function submit(versionString, opts) {
  requireVersion(versionString);
  const app = await appId();
  const version = await findVersion(app, versionString);
  if (!version) fail(`Version ${versionString} does not exist; run prepare first.`);
  const a = version.attributes;
  if (!EDITABLE.has(a.appStoreState) && !EDITABLE.has(a.appVersionState)) {
    fail(`Version ${versionString} is ${a.appVersionState} (${a.appStoreState}); there is nothing to submit.`);
  }
  if (a.releaseType !== "MANUAL") fail("Release type is not MANUAL; run prepare first.");
  const build = await versionBuild(version.id);
  if (!build) fail("No build is attached; run prepare first.");
  const loc = await localization(version.id);
  if (!loc?.attributes.whatsNew?.trim()) fail(`${LOCALE} What's New is empty; run prepare first.`);

  const all = await submissions(app);
  const blocking = all.find((s) => ["UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW"].includes(s.attributes.state));
  if (blocking) {
    fail(
      `Review submission ${blocking.id} is ${blocking.attributes.state}. ` +
        "Resolve or resubmit it in App Store Connect; this client only starts fresh submissions.",
    );
  }

  const plan = new Plan(opts.apply);
  let submission = all.find((s) => s.attributes.state === "READY_FOR_REVIEW");
  if (!submission) {
    const created = await plan.send("Create review submission", "POST", "/v1/reviewSubmissions", {
      data: {
        type: "reviewSubmissions",
        attributes: { platform: "IOS" },
        relationships: { app: { data: { type: "apps", id: app } } },
      },
    });
    submission = created?.data ?? null;
  }
  const items = submission ? await submissionItems(submission.id) : [];
  const others = items.filter((i) => i.relationships?.appStoreVersion?.data?.id !== version.id);
  if (others.length) {
    fail(`Draft submission ${submission.id} already holds other items; review it in App Store Connect.`);
  }
  if (!items.length) {
    await plan.send(`Add version ${versionString} (build ${build.attributes.version})`, "POST", "/v1/reviewSubmissionItems", {
      data: {
        type: "reviewSubmissionItems",
        relationships: {
          reviewSubmission: { data: { type: "reviewSubmissions", id: submission?.id ?? "<new submission>" } },
          appStoreVersion: { data: { type: "appStoreVersions", id: version.id } },
        },
      },
    });
  }
  const id = submission?.id ?? "<new submission>";
  await plan.send("Submit for App Review", "PATCH", `/v1/reviewSubmissions/${id}`, {
    data: { type: "reviewSubmissions", id, attributes: { submitted: true } },
  });

  plan.finish();
  if (opts.apply) await status(versionString);
}

// The API equivalent of "Release This Version" for an approved manual release.
async function release(versionString, opts) {
  requireVersion(versionString);
  const version = await findVersion(await appId(), versionString);
  if (!version) fail(`Version ${versionString} does not exist.`);
  const state = version.attributes.appStoreState;
  if (state !== "PENDING_DEVELOPER_RELEASE") {
    fail(`Version ${versionString} is ${state}; only a PENDING_DEVELOPER_RELEASE version can be released.`);
  }
  const plan = new Plan(opts.apply);
  await plan.send(`Release version ${versionString} to the App Store`, "POST", "/v1/appStoreVersionReleaseRequests", {
    data: {
      type: "appStoreVersionReleaseRequests",
      relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version.id } } },
    },
  });
  plan.finish();
  if (opts.apply) await status(versionString);
}

// The App Store listing against docs/release/listing.json: description, keywords and
// promotional text, plus the 6.9" screenshot set when --screenshots names the generated
// directory. Promotional text can change on a live version; the rest only on an editable one.
async function listing(versionString, opts) {
  requireVersion(versionString);
  const wanted = JSON.parse(readFileSync(LISTING_PATH, "utf8"));
  const app = await appId();
  const version = await findVersion(app, versionString);
  if (!version) fail(`Version ${versionString} does not exist; run prepare first.`);
  const { appStoreState, appVersionState } = version.attributes;
  const editable = EDITABLE.has(appStoreState) || EDITABLE.has(appVersionState);
  const { data: locs } = await get(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
  const loc = locs.find((l) => l.attributes.locale === LOCALE);
  if (!loc) fail(`Version ${versionString} has no ${LOCALE} localization.`);

  console.log(`Version ${versionString}: ${appVersionState}${editable ? "" : " (only promotional text can change)"}`);
  const fields = { description: "description", promotionalText: "promotional text", keywords: "keywords" };
  const changes = {};
  for (const [field, label] of Object.entries(fields)) {
    const current = (loc.attributes[field] ?? "").trim();
    const target = wanted[field].trim();
    if (current === target) {
      console.log(`  ${label}: matches listing.json`);
    } else {
      console.log(`  ${label}: differs\n    App Store:    ${oneLine(current)}\n    listing.json: ${oneLine(target)}`);
      changes[field] = target;
    }
  }
  if (wanted.promotionalText.length > 170) fail(`Promotional text is ${wanted.promotionalText.length} characters; the limit is 170.`);
  if (wanted.keywords.length > 100) fail(`Keywords are ${wanted.keywords.length} characters; the limit is 100.`);
  if (wanted.description.length > 4000) fail(`Description is ${wanted.description.length} characters; the limit is 4000.`);

  const { data: sets } = await get(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`);
  const set = sets.find((s) => s.attributes.screenshotDisplayType === SCREENSHOT_DISPLAY_TYPE);
  // The relationship lists the set in display order; the collection endpoint does not promise one.
  const unordered = set ? (await get(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=10`)).data : [];
  const order = set ? (await get(`/v1/appScreenshotSets/${set.id}/relationships/appScreenshots?limit=10`)).data.map((r) => r.id) : [];
  const current = order.map((id) => unordered.find((s) => s.id === id)).filter(Boolean);
  console.log(`  screenshots (${SCREENSHOT_DISPLAY_TYPE}): ${current.map((s) => s.attributes.fileName).join(", ") || "none"}`);

  let files = [];
  let screenshotsDiffer = false;
  if (opts.screenshots) {
    files = readdirSync(opts.screenshots)
      .filter((f) => f.endsWith(".png"))
      .sort()
      .map((name) => {
        const path = `${opts.screenshots}/${name}`;
        const bytes = readFileSync(path);
        return { name, path, bytes, size: statSync(path).size, md5: createHash("md5").update(bytes).digest("hex") };
      });
    const approved = JSON.parse(readFileSync(APPROVED_LISTING_PATH, "utf8")).appStore;
    const unapproved = files.filter((f) => approved[f.name] !== f.md5).map((f) => f.name);
    const absent = Object.keys(approved).filter((name) => !files.some((f) => f.name === name));
    if (unapproved.length || absent.length) {
      fail(
        `${opts.screenshots} is not the approved set in docs/release/listing-approved.json` +
          `${unapproved.length ? `; differs: ${unapproved.join(", ")}` : ""}${absent.length ? `; missing: ${absent.join(", ")}` : ""}.`,
      );
    }
    screenshotsDiffer =
      files.length !== current.length ||
      files.some((f, i) => current[i]?.attributes.sourceFileChecksum !== f.md5);
    console.log(`  screenshots: ${screenshotsDiffer ? `differ from ${opts.screenshots}` : `match ${opts.screenshots}`}`);
  }

  const lockedChanges = Object.keys(changes).filter((f) => f !== "promotionalText");
  if (!editable && (lockedChanges.length || screenshotsDiffer)) {
    console.log(`  ${[...lockedChanges, ...(screenshotsDiffer ? ["screenshots"] : [])].join(", ")} need an editable version; only promotional text will change.`);
    for (const f of lockedChanges) delete changes[f];
    screenshotsDiffer = false;
  }

  const plan = new Plan(opts.apply);
  if (Object.keys(changes).length) {
    await plan.send(`Set ${LOCALE} ${Object.keys(changes).map((f) => fields[f]).join(", ")}`, "PATCH",
      `/v1/appStoreVersionLocalizations/${loc.id}`,
      { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: changes } });
  }
  if (screenshotsDiffer) {
    let setId = set?.id;
    if (!setId) {
      const created = await plan.send(`Create the ${SCREENSHOT_DISPLAY_TYPE} screenshot set`, "POST", "/v1/appScreenshotSets", {
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: SCREENSHOT_DISPLAY_TYPE },
          relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc.id } } },
        },
      });
      setId = created?.data.id ?? "<new set>";
    }
    // Upload before deleting, so a failed run leaves the old set rather than a partial one.
    // Only what the slot cannot hold alongside the new files goes first.
    const overflow = Math.max(0, current.length + files.length - SCREENSHOT_SLOT_LIMIT);
    const deleteScreenshot = (old) =>
      plan.send(`Delete old screenshot ${old.attributes.fileName}`, "DELETE", `/v1/appScreenshots/${old.id}`);
    for (const old of current.slice(0, overflow)) await deleteScreenshot(old);
    const uploaded = [];
    for (const file of files) {
      const reserved = await plan.send(`Upload ${file.name} (${file.size} bytes)`, "POST", "/v1/appScreenshots", {
        data: {
          type: "appScreenshots",
          attributes: { fileName: file.name, fileSize: file.size },
          relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: setId } } },
        },
      });
      if (!reserved) continue;
      for (const op of reserved.data.attributes.uploadOperations) {
        const headers = Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value]));
        const res = await fetch(op.url, {
          method: op.method,
          headers,
          body: file.bytes.subarray(op.offset, op.offset + op.length),
        });
        if (!res.ok) fail(`Uploading ${file.name} failed: HTTP ${res.status}`);
      }
      await api("PATCH", `/v1/appScreenshots/${reserved.data.id}`, {
        data: { type: "appScreenshots", id: reserved.data.id, attributes: { uploaded: true, sourceFileChecksum: file.md5 } },
      });
      uploaded.push(reserved.data.id);
    }
    if (opts.apply) await waitForScreenshots(uploaded);
    for (const old of current.slice(overflow)) await deleteScreenshot(old);
    await plan.send(`Order the ${files.length} screenshots as listed`, "PATCH",
      `/v1/appScreenshotSets/${setId}/relationships/appScreenshots`,
      { data: uploaded.map((id) => ({ type: "appScreenshots", id })) });
  }
  plan.finish();
}

// App Store Connect processes each upload before it counts toward the set.
async function waitForScreenshots(ids) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const states = await Promise.all(
      ids.map(async (id) => (await get(`/v1/appScreenshots/${id}?fields[appScreenshots]=fileName,assetDeliveryState`)).data),
    );
    const failed = states.filter((s) => s.attributes.assetDeliveryState?.state === "FAILED");
    if (failed.length) {
      fail(`Processing failed: ${failed.map((s) => `${s.attributes.fileName} ${JSON.stringify(s.attributes.assetDeliveryState.errors)}`).join("; ")}`);
    }
    if (states.every((s) => s.attributes.assetDeliveryState?.state === "COMPLETE")) {
      console.log(`     ${ids.length} screenshots processed`);
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 4000));
  }
  fail("Screenshots are still processing after two minutes; rerun listing to check them.");
}

function oneLine(text) {
  const flat = text.replaceAll("\n", " ⏎ ");
  return flat.length > 140 ? `${flat.slice(0, 140)}…` : flat || "(empty)";
}

// ---------- helpers ----------

class Plan {
  constructor(apply) {
    this.apply = Boolean(apply);
    this.steps = 0;
    console.log(this.apply ? "Applying:" : "Plan (dry run; rerun with --apply to send):");
  }
  async send(label, method, path, body) {
    this.steps += 1;
    console.log(`  ${this.steps}. ${label}  [${method} ${path}]`);
    if (!this.apply) return null;
    const result = await api(method, path, body);
    console.log("     done");
    return result;
  }
  finish() {
    if (!this.steps) console.log("  nothing to change");
  }
}

function requireVersion(v) {
  if (!/^\d+\.\d+(\.\d+)?$/.test(v ?? "")) fail(`Expected a version like 1.5, got "${v ?? ""}".`);
}

function indent(text, n) {
  return text
    .split("\n")
    .map((l) => " ".repeat(n) + l)
    .join("\n");
}

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function parse(argv) {
  const positional = [];
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) opts[key] = true;
      else opts[key] = argv[++i];
    } else positional.push(argv[i]);
  }
  return { positional, opts };
}

const [command, ...rest] = process.argv.slice(2);
const { positional, opts } = parse(rest);
const commands = {
  check: () => check(),
  runs: () => runs(opts),
  versions: () => versions(opts),
  status: () => status(positional[0]),
  prepare: () => prepare(positional[0], opts),
  submit: () => submit(positional[0], opts),
  release: () => release(positional[0], opts),
  listing: () => listing(positional[0], opts),
};
if (!commands[command]) {
  console.error("usage: asc.mjs check | runs [--build <n>] [--commit <sha>] [--branch <name>] | versions | status <v> | prepare <v> --build <n> --whats-new <file> [--apply] | submit <v> [--apply] | release <v> [--apply] | listing <v> [--screenshots <dir>] [--apply]");
  process.exit(2);
}
await commands[command]();
