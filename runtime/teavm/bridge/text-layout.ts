/// <reference path="./text-libraries.d.ts" />
/** Android plain-text layout integration; Unicode rules belong to the libraries. */
import LineBreaker from 'linebreak';
import bidiFactory from 'bidi-js';

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
const fail = (message: string): never => {
  throw Object.assign(Error(message), { code: 'limit_exceeded' });
};
export function layoutText(
  input: TextLayoutInput,
  measure: (text: string) => TextMeasurement,
): TextLayout {
  const { text, width, alignment, spacingMult, spacingAdd, includePad } = input;
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
  const opportunities: { position: number; required: boolean }[] = [];
  const breaker = new LineBreaker(text);
  for (let point = breaker.nextBreak(); point; point = breaker.nextBreak()) {
    if (safe.has(point.position)) opportunities.push(point);
  }
  if (text.length && opportunities.at(-1)?.position !== text.length)
    opportunities.push({ position: text.length, required: false });
  const paragraphs = bidi.getEmbeddingLevels(text).paragraphs;
  let measuredUnits = 0,
    calls = 0;
  const metrics = (start: number, end: number) => {
    if (++calls > 32768 || (measuredUnits += end - start + 2) > 1024 * 1024)
      fail('Text shaping work budget exceeded');
    const result = measure(text.slice(start, end));
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
  }[] = [];
  let start = 0,
    pointIndex = 0,
    boundaryIndex = 0;
  while (start < text.length) {
    if (rows.length >= TEXT_LINES) fail('Text exceeds 512 lines');
    while (
      opportunities[pointIndex] &&
      opportunities[pointIndex]!.position <= start
    )
      pointIndex++;
    let last = pointIndex;
    while (last + 1 < opportunities.length && !opportunities[last]!.required)
      last++;
    let lo = pointIndex,
      hi = last,
      chosen = -1;
    while (lo <= hi) {
      const middle = (lo + hi) >>> 1,
        end = opportunities[middle]!.position;
      if (metrics(start, fitEnd(start, end)).width <= width) {
        chosen = middle;
        lo = middle + 1;
      } else hi = middle - 1;
    }
    let end: number;
    if (chosen >= 0) end = opportunities[chosen]!.position;
    else {
      while (
        boundaries[boundaryIndex] !== undefined &&
        boundaries[boundaryIndex]! <= start
      )
        boundaryIndex++;
      const stop = opportunities[pointIndex]!.position;
      let lastBoundary = boundaryIndex;
      while (
        lastBoundary + 1 < boundaries.length &&
        boundaries[lastBoundary + 1]! <= stop
      )
        lastBoundary++;
      lo = boundaryIndex;
      hi = lastBoundary;
      let fit = -1;
      while (lo <= hi) {
        const middle = (lo + hi) >>> 1;
        if (metrics(start, fitEnd(start, boundaries[middle]!)).width <= width) {
          fit = middle;
          lo = middle + 1;
        } else hi = middle - 1;
      }
      // Android also makes progress if one grapheme is wider than the line.
      end = boundaries[fit >= 0 ? fit : boundaryIndex]!;
    }
    const visible = visibleEnd(start, end),
      paragraph = paragraphs.find(
        (item) => start >= item.start && start <= item.end,
      );
    rows.push({
      start,
      end,
      visible,
      metrics: metrics(start, visible),
      rawWidth: metrics(start, end).width,
      direction: paragraph && paragraph.level & 1 ? -1 : 1,
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
