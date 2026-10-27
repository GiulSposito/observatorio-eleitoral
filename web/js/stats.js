// Estatística descritiva de exibição (docs/02 §4.4, achado A3): correlação de Pearson entre
// variações por seção, normalizadas por aptos, com intervalo de Fisher e mínimo de seções.
// Não é inferência sobre eleitores; é a descrição das seções carregadas. Puro, sem DOM.

export function pearson(xs, ys) {
  const n = xs.length;
  if (n !== ys.length || n < 3) return null;
  let mx = 0;
  let my = 0;
  for (let i = 0; i < n; i += 1) { mx += xs[i]; my += ys[i]; }
  mx /= n; my /= n;
  let sxy = 0;
  let sxx = 0;
  let syy = 0;
  for (let i = 0; i < n; i += 1) {
    const dx = xs[i] - mx;
    const dy = ys[i] - my;
    sxy += dx * dy; sxx += dx * dx; syy += dy * dy;
  }
  if (sxx === 0 || syy === 0) return null;
  return sxy / Math.sqrt(sxx * syy);
}

// Intervalo de 95% pela transformação de Fisher.
export function fisherInterval(r, n, z = 1.959963985) {
  if (r == null || n < 4) return null;
  const clamped = Math.max(-0.999999, Math.min(0.999999, r));
  const zr = Math.atanh(clamped);
  const se = 1 / Math.sqrt(n - 3);
  return [Math.tanh(zr - z * se), Math.tanh(zr + z * se)];
}

// points: [{x, y}] já normalizados. minN: mínimo de seções para mostrar o coeficiente.
export function correlationSummary(points, minN) {
  const valid = points.filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));
  const n = valid.length;
  if (n < minN) return { n, r: null, interval: null, reason: "few_sections" };
  const r = pearson(valid.map((p) => p.x), valid.map((p) => p.y));
  if (r == null) return { n, r: null, interval: null, reason: "no_variation" };
  return { n, r, interval: fisherInterval(r, n), reason: null };
}
