export interface KMeansResult {
  assignments: number[];
  centroids: number[][];
  k: number;
}

function cosineDistance(a: number[], b: number[]): number {
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  const denom = Math.sqrt(na) * Math.sqrt(nb);
  if (denom === 0) return 1;
  return 1 - dot / denom;
}

function pickInitialCentroids(vectors: number[][], k: number, seed = 42): number[][] {
  let s = seed;
  const rand = () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
  const n = vectors.length;
  const firstIdx = Math.floor(rand() * n);
  const centroids: number[][] = [vectors[firstIdx]];
  while (centroids.length < k) {
    const distances = vectors.map((v) =>
      Math.min(...centroids.map((c) => cosineDistance(v, c) ** 2))
    );
    const total = distances.reduce((a, b) => a + b, 0);
    if (total === 0) {
      centroids.push(vectors[Math.floor(rand() * n)]);
      continue;
    }
    let r = rand() * total;
    let chosen = 0;
    for (let i = 0; i < distances.length; i++) {
      r -= distances[i];
      if (r <= 0) {
        chosen = i;
        break;
      }
    }
    centroids.push(vectors[chosen]);
  }
  return centroids.map((c) => [...c]);
}

export function kmeans(
  vectors: number[][],
  k: number,
  maxIters = 30
): KMeansResult {
  if (vectors.length === 0) return { assignments: [], centroids: [], k };
  const effectiveK = Math.min(k, vectors.length);
  let centroids = pickInitialCentroids(vectors, effectiveK);
  const assignments = new Array(vectors.length).fill(0);
  const dim = vectors[0].length;

  for (let iter = 0; iter < maxIters; iter++) {
    let changed = false;
    for (let i = 0; i < vectors.length; i++) {
      let bestJ = 0;
      let bestD = Infinity;
      for (let j = 0; j < effectiveK; j++) {
        const d = cosineDistance(vectors[i], centroids[j]);
        if (d < bestD) {
          bestD = d;
          bestJ = j;
        }
      }
      if (assignments[i] !== bestJ) {
        assignments[i] = bestJ;
        changed = true;
      }
    }
    const sums: number[][] = Array.from({ length: effectiveK }, () =>
      new Array(dim).fill(0)
    );
    const counts = new Array(effectiveK).fill(0);
    for (let i = 0; i < vectors.length; i++) {
      const a = assignments[i];
      counts[a]++;
      const v = vectors[i];
      const s = sums[a];
      for (let d = 0; d < dim; d++) s[d] += v[d];
    }
    for (let j = 0; j < effectiveK; j++) {
      if (counts[j] > 0) {
        centroids[j] = sums[j].map((x) => x / counts[j]);
      }
    }
    if (!changed) break;
  }
  return { assignments, centroids, k: effectiveK };
}

export function pickK(n: number): number {
  if (n <= 6) return Math.max(1, Math.floor(n / 2));
  if (n <= 20) return 3;
  if (n <= 60) return 5;
  if (n <= 150) return 7;
  return 9;
}
