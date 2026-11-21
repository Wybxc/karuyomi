/// <reference path="./text-libraries.d.ts" />
import createHyphenator from 'hyphen';
import german from 'hyphen/patterns/de-1996.js';
import britishEnglish from 'hyphen/patterns/en-gb.js';
import americanEnglish from 'hyphen/patterns/en-us.js';
import spanish from 'hyphen/patterns/es.js';
import french from 'hyphen/patterns/fr.js';
import indonesian from 'hyphen/patterns/id.js';
import italian from 'hyphen/patterns/it.js';
import portuguese from 'hyphen/patterns/pt.js';

const softHyphen = '\u00ad';
const dictionaries = new Map([
  ['de', german],
  ['en', americanEnglish],
  ['en-GB', britishEnglish],
  ['es', spanish],
  ['fr', french],
  ['id', indonesian],
  ['it', italian],
  ['pt', portuguese],
]);

export function dictionaryBreaks(
  text: string,
  languageTag: string,
  graphemeEnds: ReadonlySet<number>,
): number[] {
  const locale = new Intl.Locale(languageTag);
  const patterns =
    dictionaries.get(locale.baseName) ?? dictionaries.get(locale.language);
  if (!patterns) return [];
  // The library caches words inside the returned function. Scope it to this layout.
  const hyphenate = createHyphenator(patterns);
  const segmenter = new Intl.Segmenter(locale.baseName, {
    granularity: 'word',
  });
  const breaks: number[] = [];
  for (const { index, segment, isWordLike } of segmenter.segment(text)) {
    if (!isWordLike || segment.includes(softHyphen)) continue;
    const parts = hyphenate(segment).split(softHyphen);
    let position = index;
    for (const part of parts.slice(0, -1)) {
      position += part.length;
      if (graphemeEnds.has(position)) breaks.push(position);
    }
  }
  return breaks;
}
