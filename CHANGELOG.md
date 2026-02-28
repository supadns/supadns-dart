## 1.0.0

- Initial release.
- Added `resolveDoH` for standalone DoH queries (Quad9 + Cloudflare fallback).
- Added `smartFetch` for a drop-in networking bypass wrapper around `HttpClient`.
- Added `createSmartClient` as a drop-in replacement for the standard `SupabaseClient` preserving perfect TLS SNI.
