# SupaDNS (Dart)

Bypass blocked DNS for Supabase using DNS-over-HTTPS.

## Install

```yaml
dependencies:
  supadns: ^1.0.0
```

## Usage

```dart
import 'package:supadns/supadns.dart';

// Resolve via DoH
final ip = await resolveDoH('myproject.supabase.co');
print('Resolved: $ip');

// Smart fetch with auto DoH fallback
final resp = await smartFetch(
  'https://myproject.supabase.co/rest/v1/todos',
  headers: {'apikey': 'your-anon-key'},
);
```

## How It Works

1. Tries normal system DNS first
2. On DNS failure for `*.supabase.co`, resolves via DoH (Quad9 → Cloudflare)
3. Connects to resolved IP with correct TLS SNI via `SecureSocket.connect(host:)`

## Requirements

- Dart ≥ 3.0
