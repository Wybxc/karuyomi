import { expect, test } from 'vitest';
import {
  categoryMutationSchema,
  categoryCatalogResponseSchema,
  mangaStateResponseSchema,
  stateMutationSchema,
} from '../src/business-state.ts';

const id = 'f99489f0-3f30-4d7c-8cb1-0f456c40319d';
const other = '5c70b182-c978-4650-b1d0-6c87c33c1048';
const base = {
  schemaVersion: 1,
  mutationId: 'a281b912-5bdb-4640-b7bc-d33bd721f8c4',
  expectedRevision: 0,
};
const create = (name: string, categoryId = id) => ({
  ...base,
  createCategory: { category: { id: categoryId, name } },
});

test('category names count Unicode scalars and UTF-8 bytes, require trimmed valid text and UUIDv4 identities', () => {
  expect(() =>
    categoryMutationSchema.parse(create('😀'.repeat(64))),
  ).not.toThrow();
  expect(() =>
    categoryMutationSchema.parse(create('字'.repeat(85))),
  ).not.toThrow();
  expect(() =>
    categoryMutationSchema.parse(create('a'.repeat(100))),
  ).not.toThrow();
  for (const name of [
    '',
    ' trailing ',
    'a'.repeat(101),
    '😀'.repeat(65),
    '\ud800',
  ]) {
    expect(() => categoryMutationSchema.parse(create(name))).toThrow();
  }
  expect(() =>
    categoryMutationSchema.parse(create('ok', id.replace('-4d7c-', '-1d7c-'))),
  ).toThrow();
});

test('category operations reject duplicates, over-budget lists, missing operations and multiple oneof values', () => {
  for (const request of [
    base,
    { ...create('name'), deleteCategory: { categoryId: id } },
    { ...base, reorderCategories: { categoryIds: [id, id] } },
    {
      ...base,
      reorderCategories: {
        categoryIds: Array.from({ length: 65 }, () => crypto.randomUUID()),
      },
    },
    { ...base, renameCategory: { categoryId: id, name: ' wrong ' } },
    { ...base, deleteCategory: { categoryId: 'invalid' } },
  ])
    expect(() => categoryMutationSchema.parse(request)).toThrow();
  expect(() =>
    categoryMutationSchema.parse({
      ...base,
      reorderCategories: { categoryIds: [] },
    }),
  ).not.toThrow();
  expect(() =>
    stateMutationSchema.parse({
      ...base,
      mangaKey: 'a'.repeat(64),
      setCategories: { categoryIds: [id], expectedCatalogRevision: 4294967296 },
    }),
  ).toThrow();
  expect(() =>
    stateMutationSchema.parse({
      ...base,
      mangaKey: 'a'.repeat(64),
      setCategories: { categoryIds: [id, id], expectedCatalogRevision: 0 },
    }),
  ).toThrow();
});

test('successful state replies require a bounded catalog and category identities projected in its order', () => {
  const categories = [
    { id, name: '同名' },
    { id: other, name: '同名' },
  ];
  const response = {
    schemaVersion: 1,
    accountRevision: 1,
    manga: { mangaKey: 'a'.repeat(64), categoryIds: [id, other] },
    categoryCatalog: { revision: 1, categories },
  };
  expect(() => mangaStateResponseSchema.parse(response)).not.toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({ ...response, categoryCatalog: undefined }),
  ).toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({
      ...response,
      manga: { ...response.manga, categoryIds: [other, id] },
    }),
  ).toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({
      ...response,
      manga: { ...response.manga, categoryIds: [crypto.randomUUID()] },
    }),
  ).toThrow();
  expect(() =>
    categoryCatalogResponseSchema.parse({
      schemaVersion: 1,
      categoryCatalog: { categories: [categories[0], categories[0]] },
    }),
  ).toThrow();
});
