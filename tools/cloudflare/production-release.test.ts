import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertAppliedMigrations } from './production-release.ts';

const migrations = ['0000_initial.sql', '0001_history.sql'] as const;
const select = (names: readonly string[]) => [
  { success: true, results: names.map((name) => ({ name })) },
];

test('production release requires the exact ordered D1 migration ledger', () => {
  assert.doesNotThrow(() =>
    assertAppliedMigrations(migrations, select(migrations)),
  );
  assert.throws(
    () => assertAppliedMigrations(migrations, select(migrations.slice(0, 1))),
    /Production D1 is missing 0001_history.sql/,
  );
  for (const applied of [
    [...migrations].reverse(),
    [...migrations, '0002_other.sql'],
    [migrations[0], '0001_other.sql'],
  ]) {
    assert.throws(
      () => assertAppliedMigrations(migrations, select(applied)),
      /migration ledger is not a prefix/,
    );
  }
  assert.throws(() =>
    assertAppliedMigrations(migrations, [{ success: false }]),
  );
});
