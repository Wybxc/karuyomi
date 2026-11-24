import { Container } from '@cloudflare/containers';

export class SourceDnsEgress extends Container {
  defaultPort = 8080;
  enableInternet = true;
  sleepAfter = '2m';
}
