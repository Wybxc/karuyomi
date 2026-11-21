/// <reference path="./text-libraries.d.ts" />
/** Android plain-text layout integration; Unicode rules belong to the libraries. */
import LineBreaker from 'linebreak';
import bidiFactory from 'bidi-js';
import { optimizeParagraph, type BreakOpportunity } from './paragraph-break.js';
import { dictionaryBreaks } from './paragraph-hyphenation.js';

export const TEXT_UNITS = 8192;
export const TEXT_LINES = 512;
export const TEXT_DIMENSION = 16384;
export const TEXT_WORK_BYTES = 4 * 1024 * 1024;
export type TextAlignment = 'ALIGN_NORMAL' | 'ALIGN_OPPOSITE' | 'ALIGN_CENTER';
export interface FontMetrics {
  top: number;
  ascent: number;
  descent: number;
  bottom: number;
  leading: number;
}
export interface TextMeasurement extends FontMetrics {
  width: number;
}
export interface TextLayoutInput {
  text: string;
  width: number;
  alignment: TextAlignment;
  spacingMult: number;
  spacingAdd: number;
  includePad: boolean;
  breakStrategy?: number;
  hyphenationFrequency?: number;
  locale?: string;
  fontSize?: number;
}
// UTF-16 offsets match Java String; no text is duplicated in the response.
export type TextLine = [
  number,
  number,
  number,
  number,
  number,
  number,
  number,
  number,
  number,
  number,
  boolean,
];
export interface TextLayout {
  lines: TextLine[];
  height: number;
  topPadding: number;
  bottomPadding: number;
}
const bidi = bidiFactory();
export function textDirection(value: string): 1 | -1 {
  const level = bidi.getEmbeddingLevels(value).paragraphs[0]?.level ?? 0;
  return level & 1 ? -1 : 1;
}
const newline = /[\r\n\u0085\u2028\u2029]$/u;
const trailing = /[ \t\r\n\u0085\u2028\u2029]+$/u;
const layoutHyphen = '\u2010';
const fail = (message: string): never => {
  throw Object.assign(Error(message), { code: 'limit_exceeded' });
};

function lastFit(
  first: number,
  last: number,
  fits: (index: number) => boolean,
) {
  let fit = -1;
  while (first <= last) {
    const middle = (first + last) >>> 1;
    if (fits(middle)) {
      fit = middle;
      first = middle + 1;
    } else last = middle - 1;
  }
  return fit;
}

export function layoutText(
  input: TextLayoutInput,
  measure: (text: string) => TextMeasurement,
): TextLayout {
  const {
    text,
    width,
    alignment,
    spacingMult,
    spacingAdd,
    includePad,
    breakStrategy = 0,
    hyphenationFrequency = 0,
    locale = 'und',
    fontSize = 0,
  } = input;
  if (text.length > TEXT_UNITS) fail('Text exceeds 8192 UTF-16 units');
  if (
    !Number.isInteger(width) ||
    width < 0 ||
    width > TEXT_DIMENSION ||
    !Number.isFinite(spacingMult) ||
    spacingMult < 0 ||
    !Number.isFinite(spacingAdd)
  )
    throw Error('Invalid text layout dimensions or spacing');
  const segments = [
    ...new Intl.Segmenter('und', { granularity: 'grapheme' }).segment(text),
  ];
  const boundaries = segments.map(
    (segment) => segment.index + segment.segment.length,
  );
  const safe = new Set(boundaries);
  const opportunities: BreakOpportunity[] = [];
  const breaker = new LineBreaker(text);
  for (let point = breaker.nextBreak(); point; point = breaker.nextBreak()) {
    if (safe.has(point.position))
      opportunities.push({
        ...point,
        hyphen:
          point.position < text.length && text[point.position - 1] === '\u00ad',
      });
  }
  if (text.length && opportunities.at(-1)?.position !== text.length)
    opportunities.push({ position: text.length, required: false });
  const paragraphs = bidi.getEmbeddingLevels(text).paragraphs;
  const nextGrapheme = new Map(
    boundaries.map((end, index) => [boundaries[index - 1] ?? 0, end]),
  );
  const hyphens = hyphenationFrequency
    ? dictionaryBreaks(text, locale, safe).reverse()
    : [];
  let measuredUnits = 0,
    calls = 0;
  const metrics = (start: number, end: number, hyphen = false) => {
    if (++calls > 32768 || (measuredUnits += end - start + 2) > 1024 * 1024)
      fail('Text shaping work budget exceeded');
    const value = text.slice(start, end) + (hyphen ? layoutHyphen : '');
    const result = measure(value);
    for (const value of Object.values(result))
      if (!Number.isFinite(value)) throw Error('Font metrics unavailable');
    if (
      result.width < 0 ||
      result.descent < result.ascent ||
      result.bottom < result.top
    )
      throw Error('Invalid font metrics');
    return result;
  };
  const fitEnd = (start: number, end: number) =>
    end - (text.slice(start, end).match(trailing)?.[0].length ?? 0);
  const fitWidth = (start: number, point: BreakOpportunity) =>
    metrics(start, fitEnd(start, point.position), point.hyphen).width;
  const visibleEnd = (start: number, end: number) =>
    end === text.length && !newline.test(text)
      ? end
      : newline.test(text.slice(start, end))
        ? end - 1
        : fitEnd(start, end);
  const rows: {
    start: number;
    end: number;
    visible: number;
    metrics: TextMeasurement;
    rawWidth: number;
    direction: 1 | -1;
    hyphen: boolean;
  }[] = [];
  let start = 0,
    pointIndex = 0,
    boundaryIndex = 0;
  let paragraphEndIndex = -1;
  let optimized: BreakOpportunity[] = [];
  let optimizedIndex = 0;
  while (start < text.length) {
    if (rows.length >= TEXT_LINES) fail('Text exceeds 512 lines');
    while (
      opportunities[pointIndex] &&
      opportunities[pointIndex]!.position <= start
    )
      pointIndex++;
    if (pointIndex > paragraphEndIndex) {
      paragraphEndIndex = pointIndex;
      while (
        paragraphEndIndex + 1 < opportunities.length &&
        !opportunities[paragraphEndIndex]!.required
      )
        paragraphEndIndex++;
    }
    let point: BreakOpportunity;
    if (breakStrategy !== 0) {
      if (optimizedIndex === optimized.length) {
        optimized = optimizeParagraph(
          {
            start,
            width,
            balance: breakStrategy === 2,
            hyphenPenalty:
              (fontSize * width * (hyphenationFrequency === 1 ? 4 : 1)) / 2,
            wordBreaks: opportunities.slice(pointIndex, paragraphEndIndex + 1),
            hyphens,
            nextGrapheme,
          },
          fitWidth,
        );
        optimizedIndex = 0;
      }
      point = optimized[optimizedIndex++]!;
    } else {
      const chosen = lastFit(
        pointIndex,
        paragraphEndIndex,
        (index) => fitWidth(start, opportunities[index]!) <= width,
      );
      if (chosen >= 0) point = opportunities[chosen]!;
      else {
        const stop = opportunities[pointIndex]!.position;
        const hyphen = hyphens.find(
          (position) =>
            start < position &&
            position < stop &&
            fitWidth(start, { position, hyphen: true }) <= width,
        );
        if (hyphen !== undefined) point = { position: hyphen, hyphen: true };
        else {
          while (boundaries[boundaryIndex]! <= start) boundaryIndex++;
          let lastBoundary = boundaryIndex;
          while (boundaries[lastBoundary + 1]! <= stop) lastBoundary++;
          const fit = lastFit(
            boundaryIndex,
            lastBoundary,
            (index) =>
              fitWidth(start, { position: boundaries[index]! }) <= width,
          );
          // Preserve a complete grapheme if it is wider than the line.
          point = { position: boundaries[fit >= 0 ? fit : boundaryIndex]! };
        }
      }
    }
    const end = point.position;
    const hyphen = point.hyphen === true;
    const visible = visibleEnd(start, end),
      paragraph = paragraphs.find(
        (item) => start >= item.start && start <= item.end,
      );
    rows.push({
      start,
      end,
      visible,
      metrics: metrics(start, visible, hyphen),
      rawWidth: metrics(start, end, hyphen).width,
      direction: paragraph && paragraph.level & 1 ? -1 : 1,
      hyphen,
    });
    start = end;
  }
  if (!rows.length || newline.test(text))
    rows.push({
      start: text.length,
      end: text.length,
      visible: text.length,
      metrics: metrics(text.length, text.length),
      rawWidth: 0,
      direction: 1,
      hyphen: false,
    });
  if (rows.length > TEXT_LINES) fail('Text exceeds 512 lines');
  const topPadding = includePad
    ? Math.floor(rows[0]!.metrics.top) - Math.round(rows[0]!.metrics.ascent)
    : 0;
  const lastMetrics = rows.at(-1)!.metrics;
  const bottomPadding = includePad
    ? Math.ceil(lastMetrics.bottom) - Math.round(lastMetrics.descent)
    : 0;
  const lines: TextLine[] = [];
  let y = 0;
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index]!,
      ascent =
        index === 0 && includePad
          ? Math.floor(row.metrics.top)
          : Math.round(row.metrics.ascent),
      descent =
        index + 1 === rows.length && includePad
          ? Math.ceil(row.metrics.bottom)
          : Math.round(row.metrics.descent);
    const spacing = (descent - ascent) * (spacingMult - 1) + spacingAdd;
    const extra =
      index + 1 < rows.length
        ? Math.sign(spacing) * Math.round(Math.abs(spacing))
        : 0;
    const step = descent - ascent + extra;
    if (step < 0) throw Error('Text line spacing produces negative height');
    const left =
      alignment === 'ALIGN_CENTER'
        ? (width - row.metrics.width) / 2
        : (alignment === 'ALIGN_NORMAL') === (row.direction === 1)
          ? 0
          : width - row.metrics.width;
    lines.push([
      row.start,
      row.end,
      row.visible,
      y,
      y - ascent,
      descent + extra,
      left,
      row.metrics.width,
      row.direction,
      row.rawWidth,
      row.hyphen,
    ]);
    y += step;
  }
  const height = y;
  if (height < 0 || height > TEXT_DIMENSION)
    fail('Text layout height exceeds 16384 pixels');
  const result = { lines, height, topPadding, bottomPadding };
  if (new TextEncoder().encode(JSON.stringify(result)).length > 65536)
    fail('Text layout result exceeds 64 KiB');
  return result;
}
