import { create } from '@bufbuild/protobuf';
import {
  encodeControlRequest,
  encodeControlResponse,
  parseControlRequest,
  parseControlResponse,
  type ControlRequest,
} from '@karuyomi/contracts';
import {
  PreferenceGroupSchema,
  PreferenceNodeSchema,
  PreferenceSyncScope,
  type ControlResponseJson,
  type PreferenceNode,
  type PreferenceSnapshot,
} from '@karuyomi/protocol';

type Control = (input: unknown) => Promise<ControlResponseJson>;

const komiicSource = '792932060924485302';
const chapterPath = [0, 1, 0];

export function preferenceGroupAcceptanceControl(control: Control): Control {
  let original:
    { snapshotId: string; generation: string; index: number } | undefined;
  const audit = (event: Record<string, unknown>) =>
    console.info(
      'ACCEPTANCE_RUNTIME_CONTROL',
      JSON.stringify({ profile: 'preference-groups', ...event }),
    );
  const group = (title: string, nodes: PreferenceNode[], enabled = true) =>
    create(PreferenceNodeSchema, {
      title,
      enabled,
      visible: true,
      syncScope: PreferenceSyncScope.ACCOUNT,
      kind: { case: 'group', value: create(PreferenceGroupSchema, { nodes }) },
    });

  function groupKomiic(snapshot: PreferenceSnapshot, generation: string) {
    const index = snapshot.nodes.findIndex(
      (node) => node.key === 'CHAPTER_FILTER',
    );
    const chapters = snapshot.nodes[index];
    const mirror = snapshot.nodes.find(
      (node) => node.key === 'preferred_mirror',
    );
    if (
      snapshot.nodes.length !== 2 ||
      chapters?.kind.case !== 'choice' ||
      mirror?.kind.case !== 'choice' ||
      !chapters.enabled ||
      !mirror.enabled
    ) {
      throw new Error(
        'The acceptance fixture expected two actual Komiic choices',
      );
    }
    original = { snapshotId: snapshot.snapshotId, generation, index };
    snapshot.nodes = [
      group('阅读设置', [
        group('附加说明', []),
        group('章节列表', [chapters]),
        group('镜像设置已由分组停用', [mirror], false),
      ]),
    ];
  }

  return async (input) => {
    let request: ControlRequest;
    try {
      request = parseControlRequest(input);
    } catch {
      return control(input);
    }
    const { command } = request;
    if (command.case !== 'invoke' || command.value.sourceId !== komiicSource) {
      return control(input);
    }
    const { request: source, generation, requestId } = command.value;
    if (source.case === 'getPreferences') {
      const response = parseControlResponse(await control(input));
      const payload =
        response.result.case === 'source'
          ? response.result.value.payload
          : undefined;
      if (payload?.case === 'preferences') {
        groupKomiic(payload.value, generation);
        audit({
          event: 'grouped',
          generation,
          requestId,
          snapshotId: payload.value.snapshotId,
        });
      }
      return encodeControlResponse(response);
    }
    if (source.case !== 'editPreference') return control(input);
    const { path, snapshotId } = source.value;
    if (
      !original ||
      generation !== original.generation ||
      snapshotId !== original.snapshotId ||
      path.length !== chapterPath.length ||
      !path.every((part, index) => part === chapterPath[index])
    ) {
      audit({ event: 'rejected-path', requestId, generation, path });
      throw new Error('Unexpected edit in the grouped preference fixture');
    }
    const oldPath = [original.index];
    source.value.path = oldPath;
    const response = parseControlResponse(
      await control(encodeControlRequest(request)),
    );
    const payload =
      response.result.case === 'source'
        ? response.result.value.payload
        : undefined;
    const edit = payload?.case === 'preferenceEdit' ? payload.value : undefined;
    if (edit?.snapshot) groupKomiic(edit.snapshot, generation);
    audit({
      event: 'edited',
      requestId,
      generation,
      path,
      oldPath,
      accepted: edit?.accepted ?? false,
    });
    return encodeControlResponse(response);
  };
}
