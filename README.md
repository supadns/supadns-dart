# SupaDNS (Dart / Flutter)

**Bypass blocked DNS for Supabase using DNS-over-HTTPS (DoH).**

If your ISP blocks `*.supabase.co` via DNS poisoning, standard Supabase apps will silently fail with `SocketException: Failed host lookup`. `supadns` provides a drop-in replacement client that detects these failures and transparently routes the connection through DNS-over-HTTPS (Quad9 and Cloudflare) while preserving strict TLS SNI validation.

## Install

Add it to your `pubspec.yaml`:

```yaml
dependencies:
  supadns: ^1.0.0
  supabase: ^2.0.0
```

## Quick Start (with `supabase`)

SupaDNS provides a `createSmartClient` that acts exactly like the standard `SupabaseClient` constructor, but it intercepts requests to handle DoH fallback automatically.

```dart
import 'package:supadns/supadns.dart';

void main() async {
  // Use this instead of the standard SupabaseClient constructor
  final supabase = createSmartClient(
    'https://myproject.supabase.co',
    'your-anon-key',
  );

  // All APIs work transparently: Auth, REST, Storage, Functions
  final data = await supabase.from('todos').select('*');
  print(data);
}
```

## Using with standard HTTP

If you are just making raw HTTP requests, you can use the `smartFetch` wrapper:

```dart
import 'package:supadns/supadns.dart';
import 'dart:convert';

void main() async {
  final headers = {
    'apikey': 'your-anon-key', 
    'Authorization': 'Bearer your-anon-key'
  };
  
  // Automatically handles DoH fallback if DNS is poisoned/blocked
  final resp = await smartFetch(
    'https://myproject.supabase.co/rest/v1/todos?select=*',
    headers: headers,
  );
  
  print('Status: ${resp.statusCode}');
  
  final body = await resp.transform(utf8.decoder).join();
  print(body);
}
```

## Standalone DoH Resolution

If you just need to bypass DNS and get the IPv4 address:

```dart
import 'package:supadns/supadns.dart';

void main() async {
  final ip = await resolveDoH('myproject.supabase.co');
  print('Resolved: $ip'); // -> 76.76.21.21
}
```

## How It Works (TLS SNI Preservation)

The hardest part of direct IP connection with Cloudflare is preserving TLS SNI. Dart's standard `HttpClient` does not allow decoupling DNS resolution from the Host header easily.

1. **System DNS First**: Always tries standard `dart:io HttpClient` first. If it works, overhead is ~0ms.
2. **Failure Detection**: Catches `SocketException` and `Failed host lookup` specifically for `*.supabase.co` domains.
3. **DoH Fallback**: Resolves the IPv4 address via `https://dns.quad9.net/dns-query` (RFC 1035 wire-format).
4. **TLS SNI**: Connects a raw TCP socket to the resolved IP, then upgrades it to TLS using `SecureSocket.secure(socket, host: original_host)`. This ensures Cloudflare's strict edge SSL terminates correctly. The `SecureSocket` is then passed into `HttpClient.connectionFactory` to route the HTTP protocols.

## Requirements

- Dart ≥ 3.0

## License
MIT
