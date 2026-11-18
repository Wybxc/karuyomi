const chapters = Array.from({ length: 257 }, (_, index) => ({
  id: index + 1,
  title: `验收章节 ${index + 1}`,
}));
const englishArchive = `<!doctype html><section id="middleContainer">${chapters
  .map(({ id, title }) => `<a href="/${id}/" title="2024-1-1">${title}</a>`)
  .join('')}</section>`;
const chineseArchive = Object.fromEntries(
  chapters.map((chapter) => [chapter.id, chapter]),
);

/** Supply identical chapter signatures at the pinned sources' upstream fetch boundary. */
export const fetchMigrationChapters: typeof fetch = async (input, init) => {
  const request = new Request(input, init);
  request.signal.throwIfAborted();
  if (request.method === 'GET') {
    switch (request.url) {
      case 'https://xkcd.com/archive':
      case 'https://xkcd.com/archive/':
        return new Response(englishArchive, {
          headers: { 'Content-Type': 'text/html; charset=utf-8' },
        });
      case 'https://xkcd.tw/api/strips.json':
        return Response.json(chineseArchive);
    }
  }
  return fetch(request);
};
