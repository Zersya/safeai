enum Verdict { safe, suspicious, dangerous, unchecked }

enum ThreatType {
  socialEngineering,
  malware,
  unwantedSoftware,
  harmfulApp;

  static ThreatType? fromApi(String? value) => switch (value) {
        'SOCIAL_ENGINEERING' => ThreatType.socialEngineering,
        'MALWARE' => ThreatType.malware,
        'UNWANTED_SOFTWARE' => ThreatType.unwantedSoftware,
        'POTENTIALLY_HARMFUL_APPLICATION' => ThreatType.harmfulApp,
        _ => null,
      };

  ReasonCode get reason => switch (this) {
        ThreatType.socialEngineering => ReasonCode.gsbSocialEngineering,
        ThreatType.malware => ReasonCode.gsbMalware,
        ThreatType.unwantedSoftware => ReasonCode.gsbUnwantedSoftware,
        ThreatType.harmfulApp => ReasonCode.gsbHarmfulApp,
      };
}

enum ReasonCode {
  ipHost,
  idnHost,
  apkDownload,
  brandLookalike,
  shortenerUnresolved,
  suspiciousTld,
  userinfoInUrl,
  gsbSocialEngineering,
  gsbMalware,
  gsbUnwantedSoftware,
  gsbHarmfulApp,
  noInternet,
  serviceError,
  noApiKey;

  ThreatType? get threat => switch (this) {
        ReasonCode.gsbSocialEngineering => ThreatType.socialEngineering,
        ReasonCode.gsbMalware => ThreatType.malware,
        ReasonCode.gsbUnwantedSoftware => ThreatType.unwantedSoftware,
        ReasonCode.gsbHarmfulApp => ThreatType.harmfulApp,
        _ => null,
      };
}

enum LinkSource { manual, link, share }

class CheckResult {
  const CheckResult({
    this.id,
    required this.url,
    this.finalUrl,
    required this.verdict,
    required this.reasons,
    required this.source,
    required this.checkedAt,
  });

  final int? id;
  final String url;
  final String? finalUrl;
  final Verdict verdict;
  final List<ReasonCode> reasons;
  final LinkSource source;
  final DateTime checkedAt;

  CheckResult withId(int id) => CheckResult(
        id: id,
        url: url,
        finalUrl: finalUrl,
        verdict: verdict,
        reasons: reasons,
        source: source,
        checkedAt: checkedAt,
      );

  /// Threat types behind a dangerous verdict, in reason order.
  List<ThreatType> get threats =>
      [for (final r in reasons) if (r.threat != null) r.threat!];
}
