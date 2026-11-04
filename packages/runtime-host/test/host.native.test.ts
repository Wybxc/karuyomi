import { afterEach, expect, test, vi } from 'vitest';
import { SourceRuntimeManager } from '../src/manager.js';
import { installRuntime } from '../src/host-api.js';

vi.mock('../src/manager.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/manager.js')>();
  return {
    ...actual,
    SourceRuntimeManager: vi.fn(actual.SourceRuntimeManager),
  };
});
vi.mock('../src/host-api.js', () => ({ installRuntime: vi.fn() }));

afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllGlobals();
  vi.resetModules();
});

test.each([
  { name: 'absent', imageFiles: undefined, enabled: false },
  { name: 'disabled', imageFiles: false, enabled: false },
  { name: 'explicitly enabled', imageFiles: true, enabled: true },
  { name: 'a truthy non-boolean', imageFiles: 'true', enabled: false },
])('Native image files are $name', async ({ imageFiles, enabled }) => {
  const runtimeWindow = {
    __karuyomiNativeRuntime: {
      workerSource: '/* bundled Worker */',
      materialVersion: 'test-materials',
      ...(imageFiles === undefined ? {} : { imageFiles }),
    },
  };
  vi.stubGlobal('window', runtimeWindow);
  vi.stubGlobal('location', new URL('https://read.example/runtime/host'));
  vi.stubGlobal('__KARUYOMI_MATERIAL_VERSION__', 'test-materials');
  vi.stubGlobal('__KARUYOMI_IMAGE_CODEC_MATERIALS__', []);

  await import('../src/host.native.js');

  expect(SourceRuntimeManager).toHaveBeenCalledOnce();
  expect(vi.mocked(SourceRuntimeManager).mock.calls[0]?.[4]).toEqual({
    enabled,
    tiles: { prepare: expect.any(Function) },
  });
  expect(installRuntime).toHaveBeenCalledOnce();
  expect(runtimeWindow).not.toHaveProperty('__karuyomiNativeRuntime');
});
