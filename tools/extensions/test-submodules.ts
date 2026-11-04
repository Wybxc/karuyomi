import { git, HOST_SUBMODULE_PATHS } from './catalog.ts';

/** Real local Git submodules exercise repository discovery without a network. */
export function addTestSubmodule(root: string, name: string): void {
  git(
    root,
    '-c',
    'protocol.file.allow=always',
    'submodule',
    'add',
    '-q',
    root,
    name,
  );
}

export function addHostTestSubmodules(root: string): void {
  for (const name of HOST_SUBMODULE_PATHS) addTestSubmodule(root, name);
  git(
    root,
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    'commit',
    '-qm',
    'Pin Source host fixture dependencies',
  );
}
