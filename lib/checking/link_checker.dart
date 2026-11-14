import 'local_rules.dart';
import 'models.dart';
import 'redirect_resolver.dart';
import 'safe_browsing_client.dart';

abstract class HostConverter {
  /// Punycode form of [host], or null when it cannot be converted.
  Future<String?> toAsciiHost(String host);
}

abstract class ResultStore {
  Future<CheckResult> insert(CheckResult result);
}

class LinkChecker {
  LinkChecker({
    required ThreatSource safeBrowsing,
    required RedirectResolver resolver,
    required HostConverter hosts,
    required ResultStore history,
    DateTime Function()? clock,
  })  : _safeBrowsing = safeBrowsing,
        _resolver = resolver,
        _hosts = hosts,
        _history = history,
        _now = clock ?? DateTime.now;

  final ThreatSource _safeBrowsing;
  final RedirectResolver _resolver;
  final HostConverter _hosts;
  final ResultStore _history;
  final DateTime Function() _now;

  /// Runs the full pipeline for [url] (already extracted, http/https) and
  /// records the outcome in history.
  Future<CheckResult> check(String url, LinkSource source) async {
    final uri = Uri.parse(url);

    final host = decodedHost(uri);
    final nonAscii = host.runes.any((r) => r > 127);
    final asciiHost = nonAscii ? await _hosts.toAsciiHost(host) : null;
    final skipSafeBrowsing = nonAscii && asciiHost == null;
    final fetchUri = nonAscii && asciiHost != null ? uri.replace(host: asciiHost) : uri;

    List<Uri>? chain;
    if (!skipSafeBrowsing) {
      try {
        chain = await _resolver.resolveChain(fetchUri);
      } on Exception {
        chain = null;
      }
    }
    final hops = chain ?? [fetchUri];
    final finalUrl = chain != null && chain.length > 1 ? chain.last.toString() : null;

    final shortenerResolved = chain != null && chain.length > 1;
    final local = <ReasonCode>{
      ...evaluateLocalRules(uri, shortenerResolved: shortenerResolved),
      for (final hop in hops.skip(1))
        ...evaluateLocalRules(hop, shortenerResolved: shortenerResolved),
    };

    GsbResult? gsb;
    if (!skipSafeBrowsing) {
      gsb = await _safeBrowsing.check([
        nonAscii ? fetchUri.toString() : url,
        for (final hop in hops.skip(1)) hop.toString(),
      ]);
    }

    final Verdict verdict;
    final List<ReasonCode> reasons;
    if (gsb is GsbThreats) {
      verdict = Verdict.dangerous;
      reasons = [
        for (final t in ThreatType.values)
          if (gsb.threats.contains(t)) t.reason,
        ...local,
      ];
    } else if (local.isNotEmpty) {
      verdict = Verdict.suspicious;
      reasons = [...local, if (gsb is GsbFailed) gsb.reason];
    } else if (gsb is GsbFailed) {
      verdict = Verdict.unchecked;
      reasons = [gsb.reason];
    } else {
      verdict = Verdict.safe;
      reasons = const [];
    }

    return _history.insert(CheckResult(
      url: url,
      finalUrl: finalUrl,
      verdict: verdict,
      reasons: reasons,
      source: source,
      checkedAt: _now(),
    ));
  }
}
