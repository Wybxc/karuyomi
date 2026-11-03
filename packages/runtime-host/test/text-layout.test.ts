import { describe, expect, it } from 'vitest';
import {
  layoutText,
  textDirection,
  type TextLayoutInput,
} from '../../../runtime/teavm/bridge/text-layout.js';
const measure = (value: string) => ({
  width: [...value].length * 10,
  top: -12,
  ascent: -10,
  descent: 2,
  bottom: 3,
  leading: 0,
});
const layout = (text: string, extra: Partial<TextLayoutInput> = {}) =>
  layoutText(
    {
      text,
      width: 70,
      alignment: 'ALIGN_NORMAL',
      spacingMult: 1,
      spacingAdd: 0,
      includePad: true,
      ...extra,
    },
    measure,
  );
describe('bounded plain text layout with real Unicode rule libraries', () => {
  it('wraps UAX14 opportunities and preserves UTF16 ranges plus trailing blank paragraphs', () => {
    const result = layout('one two three');
    expect(result.lines.map((row) => row.slice(0, 3))).toEqual([
      [0, 8, 7],
      [8, 13, 13],
    ]);
    expect(result.height).toBe(27);
    const blank = layout('ab\n\n');
    expect(blank.lines.map((row) => row.slice(0, 3))).toEqual([
      [0, 3, 2],
      [3, 4, 3],
      [4, 4, 4],
    ]);
    expect(layout('').lines).toHaveLength(1);
    expect(layout('a\r\nb').lines.map((row) => row.slice(0, 3))).toEqual([
      [0, 3, 2],
      [3, 4, 4],
    ]);
  });
  it('never splits emoji ZWJ or combining graphemes when forcing a long word', () => {
    for (const text of ['👩‍👩‍👧‍👦👨‍👩‍👦', 'e\u0301e\u0301', '🇨🇳🇯🇵']) {
      const result = layout(text, { width: 0 });
      const expected = [
        ...new Intl.Segmenter('und', { granularity: 'grapheme' }).segment(text),
      ].map((item) => item.segment);
      expect(result.lines.map((row) => text.slice(row[0], row[1]))).toEqual(
        expected,
      );
    }
  });
  it('uses paragraph bidi level for normal/opposite alignment, not a script heuristic', () => {
    expect(textDirection('123 مرحبا')).toBe(-1);
    expect(textDirection('hello مرحبا')).toBe(1);
    const normal = layout('אב', { width: 100 });
    expect(normal.lines[0]![6]).toBe(80);
    expect(normal.lines[0]![8]).toBe(-1);
    expect(
      layout('אב', { width: 100, alignment: 'ALIGN_OPPOSITE' }).lines[0]![6],
    ).toBe(0);
    expect(
      layout('ab', { width: 100, alignment: 'ALIGN_CENTER' }).lines[0]![6],
    ).toBe(40);
  });
  it('applies includePad and extra spacing only between lines', () => {
    const padded = layout('a\nb', { spacingMult: 1.1, spacingAdd: 2 });
    expect(padded.topPadding).toBe(-2);
    expect(padded.bottomPadding).toBe(1);
    expect(padded.lines.map((row) => row[4])).toEqual([12, 27]);
    expect(padded.height).toBe(30);
    for (let line = 0; line < padded.lines.length; line++)
      expect(padded.lines[line]![4]).toBe(
        (padded.lines[line + 1]?.[3] ?? padded.height) - padded.lines[line]![5],
      );
    expect(layout('a\nb', { spacingMult: 2 }).height).toBe(41);
    const spaces = layout('A  ', { width: 900 });
    expect(spaces.lines[0]![2]).toBe(3);
    expect(spaces.lines[0]![7]).toBe(30);
    expect(spaces.lines[0]![9]).toBe(30);
    const hard = layout('A  \nB', { width: 900 });
    expect(hard.lines[0]![2]).toBe(3);
    expect(hard.lines[0]![7]).toBe(30);
    expect(hard.lines[0]![9]).toBe(40);
    expect(
      layout('a\nb', { spacingMult: 1.1, spacingAdd: 2, includePad: false })
        .height,
    ).toBe(27);
  });
  it('rejects excessive text, lines, height, measurement work and invalid font results', () => {
    expect(() => layout('a'.repeat(8193))).toThrow('8192');
    expect(() => layout('\n'.repeat(512))).toThrow('512');
    expect(() => layout('a\nb', { spacingAdd: 16384 })).toThrow('height');
    expect(() =>
      layoutText(
        {
          text: 'a',
          width: 1,
          alignment: 'ALIGN_NORMAL',
          spacingMult: 1,
          spacingAdd: 0,
          includePad: false,
        },
        () => ({ ...measure('a'), width: NaN }),
      ),
    ).toThrow('metrics');
    expect(() => layout('a', { spacingMult: -1 })).toThrow('spacing');
  });
});
