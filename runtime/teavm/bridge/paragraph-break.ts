export interface BreakOpportunity {
  position: number;
  required?: boolean;
  hyphen?: boolean;
  emergency?: boolean;
}

interface ParagraphBreakOptions {
  start: number;
  width: number;
  balance: boolean;
  hyphenPenalty: number;
  wordBreaks: readonly BreakOpportunity[];
  hyphens: readonly number[];
  nextGrapheme: ReadonlyMap<number, number>;
}

/** Score complete paragraphs. The high-quality strategy leaves the final line ragged. */
export function optimizeParagraph(
  options: ParagraphBreakOptions,
  measure: (start: number, point: BreakOpportunity) => number,
): BreakOpportunity[] {
  const {
    start,
    width,
    balance,
    hyphenPenalty,
    wordBreaks,
    hyphens,
    nextGrapheme,
  } = options;
  const finalBreak = wordBreaks.at(-1)!;
  const end = finalBreak.position;
  if (measure(start, finalBreak) <= width) return [finalBreak];

  const candidates: BreakOpportunity[] = [{ position: start }];
  const wordPositions = new Set<number>();
  let offset = start;
  for (const point of wordBreaks) {
    if (measure(offset, point) > width) {
      for (
        let position = nextGrapheme.get(offset)!;
        position < point.position;
        position = nextGrapheme.get(position)!
      )
        candidates.push({ position, emergency: true });
    }
    candidates.push(point);
    wordPositions.add(point.position);
    offset = point.position;
  }
  for (const position of hyphens) {
    if (start < position && position < end && !wordPositions.has(position))
      candidates.push({ position, hyphen: true });
  }
  candidates.sort((left, right) => left.position - right.position);

  const scores = new Float64Array(candidates.length).fill(Infinity);
  const previous = new Int32Array(candidates.length).fill(-1);
  scores[0] = 0;
  for (let right = 1; right < candidates.length; right++) {
    const point = candidates[right]!;
    const final = point.position === end;
    const penalty = point.emergency ? 1e10 : point.hyphen ? hyphenPenalty : 0;
    for (let left = right - 1; left >= 0; left--) {
      const from = candidates[left]!;
      if (from.position === point.position || !Number.isFinite(scores[left]!))
        continue;
      const space = width - measure(from.position, point);
      if (space < 0 && nextGrapheme.get(from.position) !== point.position)
        break;
      const lastAfterHyphen = final && !balance && from.hyphen;
      const lineCost = space < 0 ? 1e12 : final && !balance ? 0 : space * space;
      const score =
        scores[left]! +
        lineCost +
        penalty +
        (final ? 0 : 2 * hyphenPenalty) +
        (lastAfterHyphen ? 4 * hyphenPenalty : 0);
      if (score <= scores[right]!) {
        scores[right] = score;
        previous[right] = left;
      }
    }
  }
  const result: BreakOpportunity[] = [];
  let position = candidates.length - 1;
  while (position > 0) {
    if (previous[position]! < 0) throw Error('No line breaks for paragraph');
    result.push(candidates[position]!);
    position = previous[position]!;
  }
  return result.reverse();
}
