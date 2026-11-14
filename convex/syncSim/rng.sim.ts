// Seeded PRNG for the sync simulator. The double-dot file name keeps this
// test-only helper out of the Convex deploy bundle.

export class Rng {
  private state: number;

  constructor(readonly seed: number) {
    this.state = seed >>> 0 || 0x9e3779b9;
  }

  // mulberry32
  next(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  int(maxExclusive: number): number {
    return Math.floor(this.next() * maxExclusive);
  }

  real(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  chance(probability: number): boolean {
    return this.next() < probability;
  }

  pick<T>(items: readonly T[]): T {
    if (items.length === 0) {
      throw new Error("Rng.pick on an empty list");
    }
    return items[this.int(items.length)];
  }

  weighted<T extends string>(weights: Readonly<Record<T, number>>): T {
    const entries = Object.entries(weights) as [T, number][];
    const total = entries.reduce((sum, [, weight]) => sum + weight, 0);
    let roll = this.next() * total;
    for (const [key, weight] of entries) {
      roll -= weight;
      if (roll < 0) {
        return key;
      }
    }
    return entries[entries.length - 1][0];
  }
}
