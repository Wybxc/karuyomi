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
