import 'models.dart';

const _suspiciousTlds = {
  'tk', 'ml', 'ga', 'cf', 'gq', 'zip', 'mov', 'top', 'icu', 'cfd', 'sbs', //
  'cyou', 'buzz', 'rest', 'click',
};

const _shorteners = {
  'bit.ly', 's.id', 'tinyurl.com', 'cutt.ly', 'rb.gy', 'shorturl.at', //
  'is.gd', 'ow.ly', 't.ly', 'v.gd', 'lnkd.in', 't.co', 'wa.link',
};

/// Brand keyword -> domains that legitimately own it. A domain `d` covers
/// `d` itself and every subdomain of it.
const _brands = <String, List<String>>{
  'bca': ['bca.co.id', 'klikbca.com'],
  'bri': ['bri.co.id'],
  'bni': ['bni.co.id'],
  'mandiri': ['bankmandiri.co.id'],
  'bsi': ['bankbsi.co.id'],
  'btn': ['btn.co.id'],
  'cimb': ['cimbniaga.co.id'],
  'danamon': ['danamon.co.id'],
  'permata': ['permatabank.com'],
  'ocbc': ['ocbc.id', 'ocbcnisp.com'],
  'jenius': ['jenius.com'],
  'dana': ['dana.id'],
  'ovo': ['ovo.id'],
  'gopay': ['gojek.com', 'gopay.co.id'],
  'gojek': ['gojek.com', 'gopay.co.id'],
  'shopee': ['shopee.co.id', 'shopee.com'],
  'tokopedia': ['tokopedia.com', 'tokopedia.link'],
  'bpjs': ['go.id'],
  'pajak': ['go.id'],
  'pln': ['pln.co.id'],
  'pertamina': ['pertamina.com', 'mypertamina.id'],
  'telkomsel': ['telkomsel.com'],
  'whatsapp': ['whatsapp.com', 'whatsapp.net', 'wa.me'],
  'facebook': ['facebook.com', 'fb.com'],
  'instagram': ['instagram.com'],
  'google': [
    'google.com',
    'google.co.id',
    'googleusercontent.com',
    'googleapis.com',
    'googlevideo.com',
    'g.co',
    'goo.gl',
  ],
  'jne': ['jne.co.id'],
  'jnt': ['jet.co.id'],
};

/// [Uri] percent-encodes non-ASCII host characters; undo that for inspection.
String decodedHost(Uri uri) {
  try {
    return Uri.decodeComponent(uri.host);
  } on FormatException {
    return uri.host;
  }
}

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

bool _hostIn(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

Set<ReasonCode> evaluateLocalRules(
  Uri uri, {
  required bool shortenerResolved,
}) {
  final reasons = <ReasonCode>{};
  var host = decodedHost(uri).toLowerCase();
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  final labels = host.split('.');
  final tld = labels.last;
  final tokens = [
    for (final l in labels.take(labels.length - 1)) ...l.split('-'),
  ].where((t) => t.isNotEmpty);

  if (_ipv4.hasMatch(host) || host.contains(':')) {
    reasons.add(ReasonCode.ipHost);
  }
  if (labels.any((l) => l.startsWith('xn--')) ||
      host.runes.any((r) => r > 127)) {
    reasons.add(ReasonCode.idnHost);
  }
  final path = uri.path.toLowerCase();
  if (path.endsWith('.apk') || path.endsWith('.xapk') || path.endsWith('.apks')) {
    reasons.add(ReasonCode.apkDownload);
  }
  if (uri.userInfo.isNotEmpty) reasons.add(ReasonCode.userinfoInUrl);
  if (_suspiciousTlds.contains(tld)) reasons.add(ReasonCode.suspiciousTld);
  if (!shortenerResolved && _shorteners.contains(host)) {
    reasons.add(ReasonCode.shortenerUnresolved);
  }

  for (final entry in _brands.entries) {
    final keyword = entry.key;
    final matches = keyword.length < 5
        ? tokens.any((t) => t == keyword)
        : tokens.any((t) => t.contains(keyword));
    if (matches && !entry.value.any((d) => _hostIn(host, d))) {
      reasons.add(ReasonCode.brandLookalike);
      break;
    }
  }
  return reasons;
}
