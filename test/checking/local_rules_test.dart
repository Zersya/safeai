import 'package:safeai/checking/local_rules.dart';
import 'package:safeai/checking/models.dart';
import 'package:flutter_test/flutter_test.dart';

Set<ReasonCode> rules(String url, {bool resolved = false}) =>
    evaluateLocalRules(Uri.parse(url), shortenerResolved: resolved);

void main() {
  test('brand lookalike on bad TLD', () {
    expect(rules('https://bca-promo.top/klaim'),
        {ReasonCode.brandLookalike, ReasonCode.suspiciousTld});
  });
  test('official brand domain is clean', () {
    expect(rules('https://www.klikbca.com/'), isEmpty);
    expect(rules('https://bca.co.id/'), isEmpty);
  });
  test('short keyword never substring-matches', () {
    expect(rules('https://fabrication.com/'), isEmpty);
  });
  test('ip host', () {
    expect(rules('http://192.168.1.1/login'), {ReasonCode.ipHost});
  });
  test('apk download', () {
    expect(rules('https://example.com/app.apk'), {ReasonCode.apkDownload});
  });
  test('userinfo trick', () {
    expect(rules('https://bca.co.id@evil.com/'), {ReasonCode.userinfoInUrl});
  });
  test('shortener only when unresolved', () {
    expect(rules('https://bit.ly/x'), {ReasonCode.shortenerUnresolved});
    expect(rules('https://bit.ly/x', resolved: true), isEmpty);
  });
  test('punycode host', () {
    expect(rules('https://xn--bc-zka.com/'), {ReasonCode.idnHost});
  });
  test('government domain may use bpjs keyword', () {
    expect(rules('https://www.bpjs-kesehatan.go.id/'), isEmpty);
  });
  test('long keyword matches inside token', () {
    expect(rules('https://shopee-gratis.com/'), {ReasonCode.brandLookalike});
  });
}
