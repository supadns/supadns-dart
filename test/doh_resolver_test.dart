import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:supadns/src/doh_resolver.dart';

void main() {
  group('encodeDnsQuery', () {
    test('produces valid DNS query', () {
      final result = encodeDnsQuery('example.com');
      expect(result.length, greaterThan(12));
      // ID=1
      expect(result[0], 0x00);
      expect(result[1], 0x01);
      // flags: RD=1
      expect(result[2], 0x01);
      expect(result[3], 0x00);
      // QDCOUNT=1
      expect(result[4], 0x00);
      expect(result[5], 0x01);
    });
  });

  group('decodeDnsResponse', () {
    test('returns null for no answers', () {
      final buf = Uint8List.fromList([
        0x00, 0x01, 0x81, 0x80,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        // question: example.com A IN
        0x07, ...('example'.codeUnits), 0x03, ...('com'.codeUnits), 0x00,
        0x00, 0x01, 0x00, 0x01,
      ]);
      expect(decodeDnsResponse(buf), isNull);
    });

    test('decodes valid A record', () {
      final buf = Uint8List.fromList([
        0x00, 0x01, 0x81, 0x80,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        // question
        0x07, ...('example'.codeUnits), 0x03, ...('com'.codeUnits), 0x00,
        0x00, 0x01, 0x00, 0x01,
        // answer: pointer, A, IN, TTL=300, 93.184.216.34
        0xC0, 0x0C,
        0x00, 0x01, 0x00, 0x01,
        0x00, 0x00, 0x01, 0x2C,
        0x00, 0x04,
        93, 184, 216, 34,
      ]);
      final result = decodeDnsResponse(buf);
      expect(result, isNotNull);
      expect(result!.ip, '93.184.216.34');
      expect(result.ttl, 300);
    });
  });

  group('cache', () {
    setUp(() => clearCache());

    test('returns null for uncached', () {
      expect(getCached('unknown.supabase.co'), isNull);
    });

    test('stores and retrieves', () {
      setCache('test.supabase.co', '1.2.3.4', 600);
      expect(getCached('test.supabase.co'), '1.2.3.4');
    });
  });

  group('isSupabaseDomain', () {
    test('matches *.supabase.co', () {
      expect(isSupabaseDomain('myproject.supabase.co'), isTrue);
      expect(isSupabaseDomain('supabase.co'), isTrue);
    });

    test('rejects others', () {
      expect(isSupabaseDomain('google.com'), isFalse);
      expect(isSupabaseDomain('supabase.com'), isFalse);
      expect(isSupabaseDomain('notsupabase.co'), isFalse);
    });
  });

  group('resolveDoH', () {
    test('resolves supabase.co', () async {
      clearCache();
      final ip = await resolveDoH('supabase.co');
      expect(ip, isNotEmpty);
      print('Resolved supabase.co → $ip');
    });
  });
}
