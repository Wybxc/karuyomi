import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  type RuntimeHello,
} from '@karuyomi/contracts';

export function createHello(generation: string): RuntimeHello {
  return {
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    generation,
    capabilities: ['control-handshake'],
    sourceReady: false,
  };
}
