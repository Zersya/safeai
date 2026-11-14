import 'package:blockai/checking/link_checker.dart';
import 'package:blockai/checking/models.dart';
import 'package:blockai/checking/redirect_resolver.dart';
import 'package:blockai/checking/safe_browsing_client.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeThreats implements ThreatSource {
  FakeThreats(this.result);
  final GsbResult result;
  List<String> seen = [];
  @override
  Future<GsbResult> check(List<String> asciiUrls) async {
    seen = asciiUrls;
    return result;
  }
}

class FakeResolver implements RedirectResolver {
  FakeResolver(this.chain);
  final List<Uri>? chain;
  @override
  Future<List<Uri>?> resolveChain(Uri start) async => chain ?? (chain == null ? null : [start]);
}

class FakeHosts implements HostConverter {
  @override
  Future<String?> toAsciiHost(String host) async => host == 'bücher.de' ? 'xn--bcher-kva.de' : null;
}

class FakeStore implements ResultStore {
  final saved = <CheckResult>[];
  @override
  Future<CheckResult> insert(CheckResult r) async {
    saved.add(r);
    return r.withId(saved.length);
  }
}

Future<CheckResult> run(String url, GsbResult gsb,
    {List<Uri>? chain, FakeStore? store, FakeThreats? threats}) {
  return LinkChecker(
    safeBrowsing: threats ?? FakeThreats(gsb),
    resolver: FakeResolver(chain ?? [Uri.parse(url)]),
    hosts: FakeHosts(),
    history: store ?? FakeStore(),
  ).check(url, LinkSource.manual);
}

void main() {
  test('threat + local rules -> dangerous, GSB reasons first', () async {
    final r = await run(
      'https://bca-promo.top/x',
      const GsbThreats({ThreatType.socialEngineering}),
    );
    expect(r.verdict, Verdict.dangerous);
    expect(r.reasons.first, ReasonCode.gsbSocialEngineering);
    expect(r.reasons, contains(ReasonCode.brandLookalike));
    expect(r.threats, [ThreatType.socialEngineering]);
  });

  test('local rule + failed GSB -> suspicious with failure reason', () async {
    final r = await run('https://example.com/a.apk', const GsbFailed(ReasonCode.noInternet));
    expect(r.verdict, Verdict.suspicious);
    expect(r.reasons, [ReasonCode.apkDownload, ReasonCode.noInternet]);
  });

  test('failed GSB only -> unchecked', () async {
    final r = await run('https://example.com/', const GsbFailed(ReasonCode.serviceError));
    expect(r.verdict, Verdict.unchecked);
    expect(r.reasons, [ReasonCode.serviceError]);
  });

  test('clean and no rules -> safe, saved with id', () async {
    final store = FakeStore();
    final r = await run('https://example.com/', const GsbClean(), store: store);
    expect(r.verdict, Verdict.safe);
    expect(r.id, 1);
    expect(store.saved.single.url, 'https://example.com/');
  });

  test('redirect chain: final url reported, every hop sent to GSB, hop rules applied', () async {
    final threats = FakeThreats(const GsbClean());
    final r = await run(
      'https://bit.ly/x',
      const GsbClean(),
      chain: [Uri.parse('https://bit.ly/x'), Uri.parse('https://example.com/app.apk')],
      threats: threats,
    );
    expect(r.finalUrl, 'https://example.com/app.apk');
    expect(threats.seen, ['https://bit.ly/x', 'https://example.com/app.apk']);
    expect(r.verdict, Verdict.suspicious);
    expect(r.reasons, [ReasonCode.apkDownload]); // shortener resolved, so no shortener reason
  });

  test('unresolvable shortener is suspicious', () async {
    final checker = LinkChecker(
      safeBrowsing: FakeThreats(const GsbFailed(ReasonCode.noInternet)),
      resolver: FakeResolver(null),
      hosts: FakeHosts(),
      history: FakeStore(),
    );
    final r = await checker.check('https://bit.ly/x', LinkSource.link);
    expect(r.verdict, Verdict.suspicious);
    expect(r.reasons, [ReasonCode.shortenerUnresolved, ReasonCode.noInternet]);
    expect(r.source, LinkSource.link);
  });

  test('non-ASCII host is punycoded for GSB and flagged', () async {
    final threats = FakeThreats(const GsbClean());
    final r = await run('https://bücher.de/', const GsbClean(), threats: threats);
    expect(threats.seen.single, contains('xn--bcher-kva.de'));
    expect(r.reasons, contains(ReasonCode.idnHost));
  });

  test('unconvertible host skips GSB but is still suspicious', () async {
    final threats = FakeThreats(const GsbClean());
    final r = await run('https://bücher.example\u00ad.de/', const GsbClean(), threats: threats);
    expect(threats.seen, isEmpty);
    expect(r.verdict, Verdict.suspicious);
    expect(r.reasons, [ReasonCode.idnHost]);
  });
}
