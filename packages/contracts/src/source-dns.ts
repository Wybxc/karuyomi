import ipaddr from 'ipaddr.js';
import { z } from 'zod';

export const SOURCE_DNS_ADDRESS_LIMIT = 16;
export const SOURCE_DNS_TARGET_HEADER = 'x-karuyomi-dns-target';
export const SOURCE_DNS_ADDRESSES_HEADER = 'x-karuyomi-dns-addresses';
export const SOURCE_DNS_ERROR_HEADER = 'x-karuyomi-dns-error';
export const SOURCE_DNS_DECODED_HEADER = 'x-karuyomi-dns-decoded';
const ipv6GlobalUnicast = ipaddr.IPv6.parse('2000::');

export const ipAddressSchema = z.union([z.ipv4(), z.ipv6()]);

export function ipAddressBytes(address: string): number[] {
  return ipaddr.parse(address).toByteArray();
}
export const dnsHostnameSchema = z
  .string()
  .max(254)
  .regex(
    /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.?$/i,
    'Expected a qualified DNS hostname',
  )
  .refine((value) => !ipAddressSchema.safeParse(value).success);

export const customDnsUrlSchema = z
  .string()
  .max(16_384)
  .refine((value) => {
    try {
      const url = new URL(value);
      return (
        url.protocol === 'https:' &&
        !url.username &&
        !url.password &&
        dnsHostnameSchema.safeParse(url.hostname).success
      );
    } catch {
      return false;
    }
  }, 'Custom DNS requires a named HTTPS destination');

export const publicDnsAddressSchema = ipAddressSchema.refine((value) => {
  const address = ipaddr.parse(value);
  return (
    address.range() === 'unicast' &&
    (!(address instanceof ipaddr.IPv6) || address.match(ipv6GlobalUnicast, 3))
  );
}, 'Expected a public unicast IP address');

export const publicDnsAddressesSchema = z
  .array(publicDnsAddressSchema)
  .min(1)
  .max(SOURCE_DNS_ADDRESS_LIMIT);
