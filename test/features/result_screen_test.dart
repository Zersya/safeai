import 'dart:convert';
import 'dart:io';

import 'package:blockai/checking/link_checker.dart';
import 'package:blockai/checking/models.dart';
import 'package:blockai/checking/redirect_resolver.dart';
import 'package:blockai/checking/safe_browsing_client.dart';
import 'package:blockai/core/native_bridge.dart';
import 'package:blockai/data/settings_repository.dart';
import 'package:blockai/features/result/result_cubit.dart';
import 'package:blockai/features/result/result_screen.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Threats implements ThreatSource {
  _Threats(this.result);
  final GsbResult result;
  @override
  Future<GsbResult> check(List<String> asciiUrls) async => result;
}

class _Resolver implements RedirectResolver {
  @override
  Future<List<Uri>?> resolveChain(Uri start) async => [start];
}

class _Hosts implements HostConverter {
  @override
  Future<String?> toAsciiHost(String host) async => host;
}

class _Store implements ResultStore {
  @override
  Future<CheckResult> insert(CheckResult r) async => r.withId(1);
}

const _channel = MethodChannel('id.blockai.app/native');

/// Pumps the result screen for [url] with a fixed Safe Browsing outcome and
/// returns the URLs handed to the native `openUrl`.
Future<List<String>> _pump(WidgetTester tester, String url, GsbResult gsb, {LinkSource source = LinkSource.manual}) async {
  SharedPreferences.setMockInitialValues({});
  final opened = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    switch (call.method) {
      case 'listBrowsers':
        return [
          {'package': 'com.android.chrome', 'label': 'Chrome'},
        ];
      case 'openUrl':
        opened.add((call.arguments as Map)['url'] as String);
        return true;
      default:
        return null;
    }
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  final checker = LinkChecker(
    safeBrowsing: _Threats(gsb),
    resolver: _Resolver(),
    hosts: _Hosts(),
    history: _Store(),
  );
  final settings = SettingsRepository(await SharedPreferences.getInstance());
  final router = GoRouter(
    initialLocation: '/result',
    initialExtra: ResultArgs(url: url, source: source),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME'))),
      GoRoute(
        path: '/result',
        builder: (_, state) => ResultScreen(args: state.extra! as ResultArgs),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: NativeBridge()),
        RepositoryProvider.value(value: settings),
        RepositoryProvider.value(value: checker),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
  return opened;
}

/// Lets platform-channel replies and futures complete, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    final json = jsonDecode(File('assets/translations/en-US.json').readAsStringSync()) as Map<String, dynamic>;
    Localization.load(const Locale('en', 'US'), translations: Translations(json));
  });

  testWidgets('dangerous: blocked, attribution + accuracy notice, no way to open', (tester) async {
    final opened = await _pump(
      tester,
      'https://evil.test/login',
      const GsbThreats({ThreatType.socialEngineering}),
    );
    expect(find.text('DANGER – do not open this link'), findsOneWidget);
    expect(find.textContaining('suspected of being deceptive'), findsOneWidget);
    expect(find.text('Advisory provided by Google'), findsOneWidget);
    expect(find.textContaining('cannot be guaranteed'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    for (final label in ['Open now', 'Open', 'Open anyway', 'Cancel']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    await tester.pump(const Duration(seconds: 5));
    expect(opened, isEmpty);
  });

  testWidgets('suspicious: no Google attribution; open only after confirmation', (tester) async {
    final opened = await _pump(tester, 'https://example.com/app.apk', const GsbClean());
    expect(find.text('Careful, this link looks suspicious'), findsOneWidget);
    expect(find.text('This link downloads an app (.apk)'), findsOneWidget);
    expect(find.text('Advisory provided by Google'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(opened, isEmpty);

    await tester.tap(find.text('Open anyway'));
    await _settle(tester);
    expect(find.text('Are you sure you want to open this suspicious link?'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.text("Don't open").last);
    await _settle(tester);
    expect(opened, isEmpty);

    await tester.tap(find.text('Open anyway'));
    await _settle(tester);
    await tester.tap(find.text('Yes, open'));
    await _settle(tester);
    expect(opened, ['https://example.com/app.apk']);
  });

  testWidgets('unchecked: retry offered, no Google attribution', (tester) async {
    await _pump(tester, 'https://example.com/', const GsbFailed(ReasonCode.noInternet));
    expect(find.text('This link could not be checked'), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open anyway'), findsOneWidget);
    expect(find.text('Advisory provided by Google'), findsNothing);
  });

  testWidgets('safe: opens automatically after the countdown', (tester) async {
    final opened = await _pump(tester, 'https://example.com/', const GsbClean());
    expect(find.text('No danger found'), findsOneWidget);
    expect(find.text('Opening in Chrome in 2…'), findsOneWidget);
    expect(opened, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(opened, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(opened, ['https://example.com/']);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('safe: Cancel stops the countdown', (tester) async {
    final opened = await _pump(tester, 'https://example.com/', const GsbClean());
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(seconds: 5));
    expect(opened, isEmpty);
    expect(find.text('Open'), findsOneWidget);
  });
}
