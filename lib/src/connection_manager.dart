import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'doh_resolver.dart';

const _initialTimeout = Duration(seconds: 10);

bool _isDnsError(dynamic err) {
  final msg = err.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('name or service not known') ||
      msg.contains('no address associated') ||
      msg.contains('timed out') ||
      msg.contains('connection refused');
}

/// fetch-like function with DoH fallback for Supabase domains.
/// Uses dart:io HttpClient for full TLS SNI control.
Future<HttpClientResponse> smartFetch(
  String url, {
  String method = 'GET',
  Map<String, String>? headers,
  List<int>? body,
  Duration timeout = _initialTimeout,
}) async {
  final uri = Uri.parse(url);

  // 1. Try normal request
  try {
    final client = HttpClient()..connectionTimeout = timeout;
    final req = await _buildRequest(client, method, uri, headers, body);
    final resp = await req.close().timeout(timeout);
    return resp;
  } catch (e) {
    if (!isSupabaseDomain(uri.host) || !_isDnsError(e)) rethrow;
  }

  // 2. DoH fallback
  return _fetchViaDoH(method, uri, headers, body, timeout);
}

Future<HttpClientResponse> _fetchViaDoH(
  String method,
  Uri uri,
  Map<String, String>? headers,
  List<int>? body,
  Duration timeout,
) async {
  final resolvedIp = await resolveDoH(uri.host);
  final port = uri.port != 0 ? uri.port : 443;

  // Create HttpClient with custom socket connection for correct TLS SNI
  final client = HttpClient();
  client.connectionTimeout = timeout;

  // Override DNS: connect to resolved IP but use original hostname for SNI
  final secureSocket = await SecureSocket.connect(
    resolvedIp,
    port,
    host: uri.host, // sets TLS SNI to the original hostname
    timeout: timeout,
  );

  // Build HTTP request over the secure socket
  final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  final requestLine = '$method $path HTTP/1.1\r\n';
  final headerLines = StringBuffer();
  headerLines.write('Host: ${uri.host}\r\n');
  headers?.forEach((k, v) => headerLines.write('$k: $v\r\n'));
  if (body != null) {
    headerLines.write('Content-Length: ${body.length}\r\n');
  }
  headerLines.write('\r\n');

  secureSocket.write(requestLine);
  secureSocket.write(headerLines.toString());
  if (body != null) secureSocket.add(body);
  await secureSocket.flush();

  // Parse response — use HttpClient with the pre-connected socket
  // For simplicity, we use a new HttpClient with a SecurityContext override
  final client2 = HttpClient();
  client2.connectionTimeout = timeout;

  // Simpler approach: use HttpClient.connectionFactory to route to resolved IP
  client2.connectionFactory =
      (Uri requestUri, String? proxyHost, int? proxyPort) async {
    return SecureSocket.connect(
      resolvedIp,
      port,
      host: uri.host,
      timeout: timeout,
    ).then((socket) => ConnectionTask<Socket>.fromSocket(socket));
  };

  // Close the manually opened socket
  await secureSocket.close();

  final req = await _buildRequest(client2, method, uri, headers, body);
  final resp = await req.close().timeout(timeout);
  return resp;
}

Future<HttpClientRequest> _buildRequest(
  HttpClient client,
  String method,
  Uri uri,
  Map<String, String>? headers,
  List<int>? body,
) async {
  final req = await client.openUrl(method, uri);
  headers?.forEach((k, v) => req.headers.set(k, v));
  if (body != null) req.add(body);
  return req;
}
