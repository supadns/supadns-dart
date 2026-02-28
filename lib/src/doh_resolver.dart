import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _dohEndpoints = [
  'https://dns.quad9.net/dns-query',
  'https://cloudflare-dns.com/dns-query',
];

const _dohTimeout = Duration(seconds: 5);
const _minTtlSeconds = 30;

// --- Cache ---

class _CacheEntry {
  final String ip;
  final DateTime expiresAt;
  _CacheEntry(this.ip, this.expiresAt);
}

final _cache = <String, _CacheEntry>{};

String? getCached(String hostname) {
  final entry = _cache[hostname];
  if (entry == null) return null;
  if (DateTime.now().isAfter(entry.expiresAt)) {
    _cache.remove(hostname);
    return null;
  }
  return entry.ip;
}

void setCache(String hostname, String ip, int ttl) {
  final effectiveTtl = ttl < _minTtlSeconds ? _minTtlSeconds : ttl;
  _cache[hostname] = _CacheEntry(
    ip,
    DateTime.now().add(Duration(seconds: effectiveTtl)),
  );
}

void clearCache() => _cache.clear();

// --- DNS wire-format (RFC 1035) ---

Uint8List encodeDnsQuery(String hostname) {
  final buf = BytesBuilder();

  // Header: ID=1, RD=1, QDCOUNT=1
  buf.add([0x00, 0x01]); // ID
  buf.add([0x01, 0x00]); // flags: RD=1
  buf.add([0x00, 0x01]); // QDCOUNT
  buf.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]); // AN/NS/AR=0

  // Question
  for (final label in hostname.split('.')) {
    buf.addByte(label.length);
    buf.add(utf8.encode(label));
  }
  buf.addByte(0x00); // root
  buf.add([0x00, 0x01]); // QTYPE=A
  buf.add([0x00, 0x01]); // QCLASS=IN

  return buf.toBytes();
}

/// Returns (ip, ttl) or null if no A record found.
({String ip, int ttl})? decodeDnsResponse(Uint8List data) {
  if (data.length < 12) return null;

  var offset = 12;
  final qdcount = (data[4] << 8) | data[5];

  // Skip questions
  for (var i = 0; i < qdcount; i++) {
    while (offset < data.length && data[offset] != 0) {
      if (data[offset] & 0xC0 == 0xC0) {
        offset += 2;
        break;
      }
      offset += data[offset] + 1;
    }
    if (offset < data.length && data[offset] == 0) offset++;
    offset += 4; // QTYPE + QCLASS
  }

  final ancount = (data[6] << 8) | data[7];
  for (var i = 0; i < ancount; i++) {
    if (offset >= data.length) break;
    // Skip name
    if (data[offset] & 0xC0 == 0xC0) {
      offset += 2;
    } else {
      while (offset < data.length && data[offset] != 0) {
        offset += data[offset] + 1;
      }
      offset++;
    }

    if (offset + 10 > data.length) break;

    final rtype = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    offset += 2; // rclass
    final ttl = (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
    offset += 4;
    final rdlength = (data[offset] << 8) | data[offset + 1];
    offset += 2;

    if (rtype == 1 && rdlength == 4 && offset + 4 <= data.length) {
      final ip =
          '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
      return (ip: ip, ttl: ttl);
    }
    offset += rdlength;
  }

  return null;
}

// --- Public API ---

/// Resolve hostname to IPv4 via DoH. Quad9 first, Cloudflare fallback.
Future<String> resolveDoH(String hostname) async {
  final cached = getCached(hostname);
  if (cached != null) return cached;

  final query = encodeDnsQuery(hostname);
  final errors = <String>[];

  for (final endpoint in _dohEndpoints) {
    try {
      final uri = Uri.parse(endpoint);
      final resp = await HttpClient()
          .postUrl(uri)
          .then((req) {
            req.headers.set(HttpHeaders.contentTypeHeader, 'application/dns-message');
            req.headers.set(HttpHeaders.acceptHeader, 'application/dns-message');
            req.contentLength = query.length;
            req.add(query);
            return req.close();
          })
          .timeout(_dohTimeout);

      if (resp.statusCode != 200) {
        errors.add('HTTP ${resp.statusCode} from $endpoint');
        await resp.drain();
        continue;
      }

      final body = await resp.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );

      final result = decodeDnsResponse(body.toBytes());
      if (result == null) {
        errors.add('no A record from $endpoint');
        continue;
      }

      setCache(hostname, result.ip, result.ttl);
      return result.ip;
    } catch (e) {
      errors.add(e.toString());
    }
  }

  throw Exception(
    'All DoH endpoints failed for $hostname: ${errors.join("; ")}',
  );
}

bool isSupabaseDomain(String hostname) {
  return hostname == 'supabase.co' || hostname.endsWith('.supabase.co');
}
