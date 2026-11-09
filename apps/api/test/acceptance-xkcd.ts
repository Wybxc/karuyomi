import type { StateMutation } from '@karuyomi/protocol';

// Stable English xkcd SINGLE /3319/ identities from the real Source.
export const xkcdMangaKey =
  '62c3d5a079471dde67f80c71005112fde078e4fa3111e6faedc9757350392a6f';
export const xkcdChapterKey =
  '3ebd1a075e8cc6fad4cae9daa7595caac80545bdf9499496417bb3d3b6b1142c';

export function xkcdLastPageCompletion(mutation: StateMutation) {
  if (
    mutation.operation.case !== 'saveProgress' ||
    mutation.mangaKey !== xkcdMangaKey
  )
    return;
  const { snapshot, progress } = mutation.operation.value;
  if (
    snapshot?.chapterKey !== xkcdChapterKey ||
    !progress?.completed ||
    !progress.current ||
    progress.current.pageKey !== snapshot.pageKeys.at(-1)
  )
    return;
  return { snapshot, progress, current: progress.current };
}
