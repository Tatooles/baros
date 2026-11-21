// Damage that older servers left in production data, recreated on a fleet:
// the server rows and every device's local store, as they ended up. Test-only.

import { type Fleet, type Kind, type LocalRecord, type SimDevice } from "./fleet.sim";

const day = 24 * 60 * 60;
const ms = (seconds: number) => Math.round(seconds * 1000);

function record(
  kind: Kind,
  id: string,
  fields: Partial<LocalRecord> & { createdAt: number; value: string },
): LocalRecord {
  return {
    kind,
    id,
    updatedAt: fields.createdAt,
    deletedAt: null,
    tag: `${id}-w0`,
    parentId: null,
    exerciseId: null,
    ...fields,
  };
}

function deleted(base: LocalRecord, at: number): LocalRecord {
  return { ...base, deletedAt: at, updatedAt: at };
}

// Devices have pulled everything seeded so far; later server writes are newer.
function catchUp(fleet: Fleet): void {
  const now = ms(fleet.time) - 1;
  for (const device of fleet.devices) {
    device.seedCursors({ exercises: now, workoutSessions: now, loggedExercises: now, loggedSets: now });
  }
}

function noteOriginal(fleet: Fleet, records: LocalRecord[]): void {
  for (const seeded of records) fleet.log.noteCreate(seeded);
}

// #97 on an older server. The deleter removed a finished workout. The
// reviver, offline, had edited its title and one set. Back online, its
// workout upload revived the workout. Its set upload hit a deleted logged
// exercise and has failed ever since (#96). Observers see an empty workout
// that the deleter does not have.
export async function seedResurrectedWorkout(
  fleet: Fleet,
  roles: { deleter: SimDevice; reviver: SimDevice; observers: SimDevice[] },
): Promise<{ sessionId: string }> {
  const t0 = fleet.time - 3 * day;
  const t1 = t0 + day;
  const t2 = t1 + 3600;
  const session = record("workoutSessions", "dmg-ws1", { createdAt: t0, value: "w-original" });
  const loggedExercise = record("loggedExercises", "dmg-le1", {
    createdAt: t0,
    value: "le-original",
    parentId: session.id,
  });
  const set1 = record("loggedSets", "dmg-set1", { createdAt: t0, value: "set1-original", parentId: loggedExercise.id });
  const set2 = record("loggedSets", "dmg-set2", { createdAt: t0, value: "set2-original", parentId: loggedExercise.id });
  const revivedSession = { ...session, value: "w-edited", tag: "dmg-ws1-w2", updatedAt: t2 };
  const editedSet1 = { ...set1, value: "set1-edited", tag: "dmg-set1-w2", updatedAt: t2 };

  await fleet.server.insertRaw(deleted(set1, t1), ms(t1) + 1);
  await fleet.server.insertRaw(deleted(set2, t1), ms(t1) + 2);
  await fleet.server.insertRaw(deleted(loggedExercise, t1), ms(t1) + 3);
  await fleet.server.insertRaw(revivedSession, ms(t2));

  for (const seeded of [session, loggedExercise, set1, set2]) {
    roles.deleter.seedRecord(deleted(seeded, t1));
  }
  roles.reviver.seedRecord(revivedSession);
  roles.reviver.seedRecord(deleted(loggedExercise, t1));
  roles.reviver.seedRecord(editedSet1);
  roles.reviver.seedRecord(deleted(set2, t1));
  roles.reviver.seedEntry("loggedSets", set1.id, "update", "failed", 40);
  for (const observer of roles.observers) {
    observer.seedRecord(revivedSession);
  }
  catchUp(fleet);

  noteOriginal(fleet, [session, loggedExercise, set1, set2]);
  fleet.log.noteWrite("workoutSessions:dmg-ws1", "w-edited");
  fleet.log.noteWrite("loggedSets:dmg-set1", "set1-edited");
  fleet.log.deleted.add("workoutSessions:dmg-ws1");
  fleet.log.trace.push("seeded resurrected workout dmg-ws1");
  return { sessionId: session.id };
}

// #98 on an older server. A device a month fast created an exercise; another
// device deleted it, and the server rejected the delete as stale. The deleter
// kept its local delete, so it disagrees with everyone else.
export async function seedFutureStampedExercise(
  fleet: Fleet,
  roles: { fastDevice: SimDevice; deleter: SimDevice; observers: SimDevice[] },
): Promise<{ exerciseId: string }> {
  const t0 = fleet.time - 2 * day;
  const t1 = t0 + day;
  const exercise = record("exercises", "dmg-ex1", { createdAt: t0 + 30 * day, value: "ex-original" });
  await fleet.server.insertRaw(exercise, ms(t0));
  roles.fastDevice.seedRecord(exercise);
  roles.deleter.seedRecord(deleted(exercise, t1));
  for (const observer of roles.observers) {
    observer.seedRecord(exercise);
  }
  catchUp(fleet);
  noteOriginal(fleet, [exercise]);
  fleet.log.deleted.add("exercises:dmg-ex1");
  fleet.log.trace.push("seeded future-stamped exercise dmg-ex1");
  return { exerciseId: exercise.id };
}

// #97 on an older server, the cascade gap. A set edit landed between the
// deleting device's set and logged-exercise tombstones, so the server holds a
// live set under a deleted workout. Every device has it deleted already.
export async function seedOrphanedLiveSet(fleet: Fleet): Promise<void> {
  const t0 = fleet.time - 3 * day;
  const t1 = t0 + day;
  const session = record("workoutSessions", "dmg-ws2", { createdAt: t0, value: "w2" });
  const loggedExercise = record("loggedExercises", "dmg-le2", { createdAt: t0, value: "le2", parentId: session.id });
  const set = record("loggedSets", "dmg-set3", { createdAt: t0, value: "set3", parentId: loggedExercise.id });
  await fleet.server.insertRaw({ ...set, value: "set3-edited", updatedAt: t1 + 1 }, ms(t1) + 2);
  await fleet.server.insertRaw(deleted(loggedExercise, t1), ms(t1) + 3);
  await fleet.server.insertRaw(deleted(session, t1), ms(t1) + 4);
  for (const device of fleet.devices) {
    for (const seeded of [session, loggedExercise, set]) device.seedRecord(deleted(seeded, t1));
  }
  catchUp(fleet);
  noteOriginal(fleet, [session, loggedExercise, set]);
  fleet.log.noteWrite("loggedSets:dmg-set3", "set3-edited");
  fleet.log.deleted.add("workoutSessions:dmg-ws2");
  fleet.log.trace.push("seeded orphaned live set dmg-set3");
}
