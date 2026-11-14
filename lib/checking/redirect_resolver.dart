import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

abstract class RedirectResolver {
  /// `[start, hop1, …]`, or null when the network fails on the first hop.
  Future<List<Uri>?> resolveChain(Uri start);
}

class HttpRedirectResolver implements RedirectResolver {
  HttpRedirectResolver(this._client);

  final http.Client _client;

  static const _maxHops = 5;
  static const _timeout = Duration(seconds: 5);
  static const _userAgent = 'Mozilla/5.0 (Linux; Android 14) safeAI/1.0';

  @override
  Future<List<Uri>?> resolveChain(Uri start) async {
    final chain = [start];
    var current = start;
    for (var hop = 0; hop < _maxHops; hop++) {
      final http.StreamedResponse response;
      try {
        var r = await _send('HEAD', current);
        if (r.statusCode == 405 || r.statusCode == 403 || r.statusCode == 501) {
          await r.stream.listen(null).cancel();
          r = await _send('GET', current);
        }
        response = r;
      } on TimeoutException {
        return chain.length == 1 ? null : chain;
      } on IOException {
        return chain.length == 1 ? null : chain;
      } on http.ClientException {
        return chain.length == 1 ? null : chain;
      }
      // Never read the body; we only care about the status and Location.
      await response.stream.listen(null).cancel();

      final location = response.headers['location'];
      if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
        final next = current.resolve(location);
        if (next.scheme != 'http' && next.scheme != 'https') break;
        chain.add(next);
        current = next;
      } else {
        break;
      }
    }
    return chain;
  }

  Future<http.StreamedResponse> _send(String method, Uri uri) {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['User-Agent'] = _userAgent;
    return _client.send(request).timeout(_timeout);
  }
}
