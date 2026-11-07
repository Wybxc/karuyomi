import assert from 'node:assert/strict';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  PATCHES,
  generateDonorSource,
  prepareSources,
} from './upstream-sources.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

test(
  'source drift, patch context drift and changed patch output fail the pinned TeaVM gates',
  {
    skip: !existsSync(path.join(ROOT, 'vendor/teavm/classlib')),
  },
  () => {
    const root = mkdtempSync(
      path.join(os.tmpdir(), 'karuyomi-upstream-drift-'),
    );
    try {
      const [packagePath, name] = PATCHES[0];
      const relative = path.join(
        'vendor/teavm/classlib/src/main/java',
        packagePath,
        `T${name}.java`,
      );
      const original = readFileSync(path.join(ROOT, relative), 'utf8');
      const patchPath = path.join(
        'runtime/teavm/patches/teavm',
        `${name}.patch`,
      );
      const patch = readFileSync(path.join(ROOT, patchPath), 'utf8');
      mkdirSync(path.dirname(path.join(root, relative)), { recursive: true });
      mkdirSync(path.dirname(path.join(root, patchPath)), { recursive: true });
      writeFileSync(path.join(root, relative), original + '\n// drift\n');
      writeFileSync(path.join(root, patchPath), patch);
      assert.throws(
        () => prepareSources(path.join(root, 'out'), root),
        /Pinned TeaVM source differs/,
      );
      writeFileSync(path.join(root, relative), original);
      writeFileSync(
        path.join(root, patchPath),
        patch.replace(
          'int rightBound = matchResult.hasAnchoringBounds()',
          'int wrongBound = matchResult.hasAnchoringBounds()',
        ),
      );
      assert.throws(
        () => prepareSources(path.join(root, 'out'), root),
        /Patch context differs/,
      );
      writeFileSync(
        path.join(root, patchPath),
        patch.replace(
          '+            matchResult.hitEnd = true; matchResult.requireEnd = true;',
          '+            matchResult.hitEnd = false; matchResult.requireEnd = true;',
        ),
      );
      assert.throws(
        () => prepareSources(path.join(root, 'out'), root),
        /Patched TeaVM source differs/,
      );
      assert.equal(
        existsSync(path.join(root, 'out', packagePath, `Patched${name}.java`)),
        false,
      );
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
);
test(
  'all pinned donor bytes remain unchanged, including intentional upstream references',
  { skip: !existsSync(path.join(ROOT, 'vendor/teavm/classlib')) },
  () => {
    const folder = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-upstream-'));
    try {
      const outputs = prepareSources(folder);
      assert.equal(outputs.length, PATCHES.length);
      assert.ok(
        outputs.every((file) => !path.relative(folder, file).startsWith('..')),
      );
      const generated = (name: string): string => {
        const entry = PATCHES.find(([, patchName]) => patchName === name);
        assert.ok(entry);
        return readFileSync(
          path.join(folder, entry[0], `Patched${name}.java`),
          'utf8',
        );
      };
      assert.ok(generated('Pattern').includes('(TPattern)(Object)this'));
      assert.ok(generated('Lexer').includes('TPattern.quote(pattern)'));
      assert.ok(
        generated('ReluctantGroupQuantifierSet').includes(
          'extends TGroupQuantifierSet',
        ),
      );
      assert.ok(
        generated('UnicodeCategoryScope').includes('extends TUnicodeCategory'),
      );
    } finally {
      rmSync(folder, { recursive: true, force: true });
    }
  },
);

test('donor generation renames Java identifiers without changing literals or unrelated trivia', () => {
  const source = `/** @see TPattern#compile(java.lang.String, int)
 * TPattern and TLexer are names in documentation.
 */
class TPattern {
  // TPattern TLexer
  String literal = "TPattern TLexer @see TPattern#compile(java.lang.String, int)";
  String block = """
    TPattern TLexer @see TPattern#compile(java.lang.String, int)
    """;
  TPatternSuffix unrelated;
  TLexer lexer;
  TPattern self;
  private TPattern() {}
}
`;
  const generated = generateDonorSource('Pattern', source);
  assert.ok(generated.includes('class PatchedPattern {'));
  assert.ok(generated.includes('private PatchedPattern() {}'));
  assert.ok(generated.includes('PatchedPattern self;'));
  assert.ok(generated.includes('PatchedLexer lexer;'));
  assert.ok(generated.includes('TPatternSuffix unrelated;'));
  assert.ok(
    generated.includes(' * TPattern and TLexer are names in documentation.'),
  );
  assert.ok(generated.includes('// TPattern TLexer'));
  assert.ok(
    generated.includes(
      '/** @see PatchedPattern#compile(java.lang.String, int)',
    ),
  );
  assert.ok(
    generated.includes(
      'String literal = "TPattern TLexer @see TPattern#compile(java.lang.String, int)";',
    ),
  );
  assert.ok(
    generated.includes(
      'String block = """\n    TPattern TLexer @see TPattern#compile(java.lang.String, int)\n    """;',
    ),
  );
});
test('missing submodule gives an actionable bootstrap instruction', () => {
  const folder = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-no-upstream-'));
  try {
    assert.throws(
      () => prepareSources(path.join(folder, 'out'), folder),
      /git submodule update/,
    );
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});
