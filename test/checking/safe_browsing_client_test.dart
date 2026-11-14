import 'dart:convert';
import 'dart:io';

import 'package:safeai/checking/models.dart';
import 'package:safeai/checking/safe_browsing_client.dart';
import 'package:safeai/checking/url_expressions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<int> evilHash() => sha256.convert(utf8.encode('evil.test/')).bytes;

// Minimal protobuf encoder for SearchHashesResponse (all lengths < 128).
List<int> _field(int tag, List<int> payload) => [tag, payload.length, ...payload];

List<int> fullHashMsg(List<int> hash, {int threatType = 2, List<int> attributes = const [], bool packed = false}) {
  final detail = [
    0x08, threatType,
    if (packed && attributes.isNotEmpty) ..._field(0x12, attributes) else for (final a in attributes) ...[0x10, a],
  ];
  return _field(0x0A, [..._field(0x0A, hash), ..._field(0x12, detail)]);
}

http.Response proto(List<int> body, {int status = 200}) =>
    http.Response.bytes(body, status, headers: {'content-type': 'application/x-protobuf'});

/// Response with a threat on evil.test/ and a 300 s cache duration.
http.Response threatResponse({int threatType = 2, List<int> attributes = const [], bool packed = false}) => proto([
      ...fullHashMsg(evilHash(), threatType: threatType, attributes: attributes, packed: packed),
      ..._field(0x12, [0x08, 0xAC, 0x02]), // seconds = 300
    ]);

void main() {
  test('exact full-hash match is a threat; query carries only prefixes', () async {
    Uri? seen;
    final c = SafeBrowsingClient(MockClient((r) async {
      seen = r.url;
      return threatResponse();
    }), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect(r, isA<GsbThreats>());
    expect((r as GsbThreats).threats, {ThreatType.socialEngineering});
    expect(seen!.path, '/v5/hashes:search');
    expect(seen!.queryParametersAll['key'], ['KEY']);
    expect(seen!.queryParameters.containsKey('alt'), isFalse);
    final prefixes = seen!.queryParametersAll['hashPrefixes']!;
    expect(prefixes, isNotEmpty);
    expect(prefixes.every((p) => base64.decode(p).length == 4), isTrue);
  });

  test('CANARY attribute is ignored', () async {
    final c = SafeBrowsingClient(MockClient((_) async => threatResponse(attributes: [1])), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('unknown threat type is ignored', () async {
    final c = SafeBrowsingClient(MockClient((_) async => threatResponse(threatType: 99)), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('empty body is clean', () async {
    final c = SafeBrowsingClient(MockClient((_) async => proto([])), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('hash for a different URL under the same prefix does not match', () async {
    final other = [...evilHash().sublist(0, 4), ...List.filled(28, 7)];
    final c = SafeBrowsingClient(MockClient((_) async => proto(fullHashMsg(other, threatType: 1))), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('packed attributes are ignored; unrelated fields are skipped', () async {
    final c = SafeBrowsingClient(MockClient((_) async => threatResponse(attributes: [2], packed: true)), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
    final d = SafeBrowsingClient(
      MockClient((_) async => proto([0x18, 0x01, ...fullHashMsg(evilHash(), threatType: 1)])),
      'KEY',
    );
    expect((await d.check(['http://evil.test/']) as GsbThreats).threats, {ThreatType.malware});
  });

  test('multiple threat types on one hash are all reported', () async {
    final hash = evilHash();
    final detail = (int t) => _field(0x12, [0x08, t]);
    final body = _field(0x0A, [..._field(0x0A, hash), ...detail(1), ...detail(4)]);
    final c = SafeBrowsingClient(MockClient((_) async => proto(body)), 'KEY');
    expect((await c.check(['http://evil.test/']) as GsbThreats).threats, {ThreatType.malware, ThreatType.harmfulApp});
  });

  test('HTTP 500 is a service error', () async {
    final c = SafeBrowsingClient(MockClient((_) async => http.Response('x', 500)), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect((r as GsbFailed).reason, ReasonCode.serviceError);
  });

  test('truncated protobuf is a service error', () async {
    final c = SafeBrowsingClient(MockClient((_) async => proto([0x0A, 0x7F, 0x01])), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect((r as GsbFailed).reason, ReasonCode.serviceError);
  });

  test('socket exception is noInternet', () async {
    final c = SafeBrowsingClient(MockClient((_) async => throw const SocketException('x')), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect((r as GsbFailed).reason, ReasonCode.noInternet);
  });

  test('empty key makes no request', () async {
    var calls = 0;
    final c = SafeBrowsingClient(MockClient((_) async {
      calls++;
      return proto([]);
    }), '');
    final r = await c.check(['http://evil.test/']);
    expect((r as GsbFailed).reason, ReasonCode.noApiKey);
    expect(calls, 0);
  });

  test('second call within cache duration makes no request; expires later', () async {
    var calls = 0;
    var now = DateTime(2025, 1, 1);
    final c = SafeBrowsingClient(MockClient((_) async {
      calls++;
      return threatResponse();
    }), 'KEY', clock: () => now);
    await c.check(['http://evil.test/']);
    final second = await c.check(['http://evil.test/']);
    expect(second, isA<GsbThreats>());
    expect(calls, 1);
    now = now.add(const Duration(minutes: 6));
    await c.check(['http://evil.test/']);
    expect(calls, 2);
  });

  test('clean answers are cached at least 5 minutes', () async {
    var calls = 0;
    var now = DateTime(2025, 1, 1);
    final c = SafeBrowsingClient(MockClient((_) async {
      calls++;
      return proto(_field(0x12, [0x08, 10]));
    }), 'KEY', clock: () => now);
    await c.check(['http://ok.test/']);
    now = now.add(const Duration(minutes: 4));
    await c.check(['http://ok.test/']);
    expect(calls, 1);
  });

  test('prefixes are chunked at 30 per request', () async {
    final sizes = <int>[];
    final c = SafeBrowsingClient(MockClient((r) async {
      sizes.add(r.url.queryParametersAll['hashPrefixes']!.length);
      return proto([]);
    }), 'KEY');
    final urls = [for (var i = 0; i < 8; i++) 'http://h$i.a.b.c.d.example.com/x/y/z/w$i.html?q=1'];
    await c.check(urls);
    expect(sizes.every((s) => s <= 30), isTrue);
    expect(sizes.length, greaterThan(1));
    expect(sizes.reduce((a, b) => a + b), fullHashes(urls.expand(expressionsFor).toSet().toList()).length);
  });
}
