import 'dart:convert';
import 'dart:io';

import 'package:blockai/checking/models.dart';
import 'package:blockai/checking/safe_browsing_client.dart';
import 'package:blockai/checking/url_expressions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String evilHash() => base64.encode(sha256.convert(utf8.encode('evil.test/')).bytes);

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object> threatBody({List<String>? attributes, String type = 'SOCIAL_ENGINEERING'}) => {
      'fullHashes': [
        {
          'fullHash': evilHash(),
          'fullHashDetails': [
            {'threatType': type, if (attributes != null) 'attributes': attributes},
          ],
        },
      ],
      'cacheDuration': '300s',
    };

void main() {
  test('exact full-hash match is a threat; query carries only prefixes', () async {
    Uri? seen;
    final c = SafeBrowsingClient(MockClient((r) async {
      seen = r.url;
      return json(threatBody());
    }), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect(r, isA<GsbThreats>());
    expect((r as GsbThreats).threats, {ThreatType.socialEngineering});
    expect(seen!.path, '/v5/hashes:search');
    expect(seen!.queryParametersAll['key'], ['KEY']);
    final prefixes = seen!.queryParametersAll['hashPrefixes']!;
    expect(prefixes, isNotEmpty);
    expect(prefixes.every((p) => base64.decode(p).length == 4), isTrue);
  });

  test('CANARY attribute is ignored', () async {
    final c = SafeBrowsingClient(MockClient((_) async => json(threatBody(attributes: ['CANARY']))), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('unknown threat type is ignored', () async {
    final c = SafeBrowsingClient(MockClient((_) async => json(threatBody(type: 'SOMETHING_NEW'))), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('empty body is clean', () async {
    final c = SafeBrowsingClient(MockClient((_) async => json({})), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('hash for a different URL under the same prefix does not match', () async {
    final other = base64.encode([
      ...sha256.convert(utf8.encode('evil.test/')).bytes.sublist(0, 4),
      ...List.filled(28, 7),
    ]);
    final body = {
      'fullHashes': [
        {'fullHash': other, 'fullHashDetails': [{'threatType': 'MALWARE'}]},
      ],
    };
    final c = SafeBrowsingClient(MockClient((_) async => json(body)), 'KEY');
    expect(await c.check(['http://evil.test/']), isA<GsbClean>());
  });

  test('url-safe unpadded hash is accepted', () async {
    final h = base64Url.encode(sha256.convert(utf8.encode('evil.test/')).bytes).replaceAll('=', '');
    final body = {
      'fullHashes': [
        {'fullHash': h, 'fullHashDetails': [{'threatType': 'MALWARE'}]},
      ],
    };
    final c = SafeBrowsingClient(MockClient((_) async => json(body)), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect((r as GsbThreats).threats, {ThreatType.malware});
  });

  test('HTTP 500 is a service error', () async {
    final c = SafeBrowsingClient(MockClient((_) async => http.Response('x', 500)), 'KEY');
    final r = await c.check(['http://evil.test/']);
    expect((r as GsbFailed).reason, ReasonCode.serviceError);
  });

  test('garbage body is a service error', () async {
    final c = SafeBrowsingClient(MockClient((_) async => http.Response('\u0001binary', 200)), 'KEY');
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
      return json({});
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
      return json(threatBody());
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
      return json({'cacheDuration': '10s'});
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
      return json({});
    }), 'KEY');
    final urls = [for (var i = 0; i < 8; i++) 'http://h$i.a.b.c.d.example.com/x/y/z/w$i.html?q=1'];
    await c.check(urls);
    expect(sizes.every((s) => s <= 30), isTrue);
    expect(sizes.length, greaterThan(1));
    expect(sizes.reduce((a, b) => a + b), fullHashes(urls.expand(expressionsFor).toSet().toList()).length);
  });
}
