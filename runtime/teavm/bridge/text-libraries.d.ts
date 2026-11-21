// Exact public APIs consumed from the pinned JS libraries, which ship no types.
declare module 'linebreak' {
  export default class LineBreaker {
    constructor(text: string);
    nextBreak(): { position: number; required: boolean } | null;
  }
}
declare module 'bidi-js' {
  export default function bidiFactory(): {
    getEmbeddingLevels(text: string): {
      levels: Uint8Array;
      paragraphs: { start: number; end: number; level: number }[];
    };
  };
}
declare module 'hyphen' {
  interface PatternTrie {
    readonly [character: string]:
      number | PatternTrie | readonly [PatternTrie, number];
  }
  export type HyphenationPatterns = readonly [
    readonly (readonly number[])[],
    PatternTrie,
    Readonly<Record<string, readonly number[]>>?,
  ];
  export default function createHyphenator(
    patterns: HyphenationPatterns,
  ): (text: string) => string;
}
declare module 'hyphen/patterns/*.js' {
  const patterns: import('hyphen').HyphenationPatterns;
  export default patterns;
}
