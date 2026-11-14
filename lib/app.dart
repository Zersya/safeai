import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'checking/link_checker.dart';
import 'checking/redirect_resolver.dart';
import 'checking/safe_browsing_client.dart';
import 'core/incoming_links.dart';
import 'core/native_bridge.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/history_repository.dart';
import 'data/settings_repository.dart';
import 'features/history/history_cubit.dart';
import 'features/settings/settings_cubit.dart';

const _safeBrowsingApiKey = String.fromEnvironment('SAFE_BROWSING_API_KEY');

class App extends StatefulWidget {
  const App({super.key, required this.settings, required this.history});

  final SettingsRepository settings;
  final HistoryRepository history;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _bridge = NativeBridge();
  final _httpClient = http.Client();
  late final GoRouter _router = buildRouter(widget.settings);
  late final LinkChecker _checker = LinkChecker(
    safeBrowsing: SafeBrowsingClient(_httpClient, _safeBrowsingApiKey),
    resolver: HttpRedirectResolver(_httpClient),
    hosts: _bridge,
    history: widget.history,
  );
  late final ProtectionCubit _protection = ProtectionCubit(_bridge);
  late final IncomingLinks _incoming = IncomingLinks(
    bridge: _bridge,
    router: _router,
    messengerKey: _messengerKey,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _incoming.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _protection.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incoming.dispose();
    _protection.close();
    _router.dispose();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: _bridge),
        RepositoryProvider.value(value: widget.settings),
        RepositoryProvider.value(value: widget.history),
        RepositoryProvider.value(value: _checker),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _protection),
          BlocProvider(create: (_) => SettingsCubit(widget.settings, _bridge)),
          BlocProvider(create: (_) => HistoryCubit(widget.history)),
        ],
        child: MaterialApp.router(
          title: 'safeAI',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          scaffoldMessengerKey: _messengerKey,
          routerConfig: _router,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
        ),
      ),
    );
  }
}
