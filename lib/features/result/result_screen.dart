import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../checking/link_checker.dart';
import '../../checking/models.dart';
import '../../core/native_bridge.dart';
import '../../core/theme.dart';
import '../../data/settings_repository.dart';
import 'result_cubit.dart';

const _advisoryUrl = 'https://developers.google.com/safe-browsing/v4/advisory';
const _socialEngineeringHelpUrl = 'https://support.google.com/webmasters/answer/6350487';
const _malwareHelpUrl =
    'https://developers.google.com/search/docs/monitor-debug/security/malware';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.args});

  final ResultArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ResultCubit(
        args: args,
        checker: context.read<LinkChecker>(),
        bridge: context.read<NativeBridge>(),
        settings: context.read<SettingsRepository>(),
      ),
      child: const _ResultView(),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView();

  /// Leaves the result screen. For links that came from another app, hands the
  /// user back to that app.
  Future<void> _leave(BuildContext context) async {
    final cubit = context.read<ResultCubit>();
    final router = GoRouter.of(context);
    if (cubit.origin != LinkSource.manual) {
      await context.read<NativeBridge>().moveToBack();
      router.go('/');
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ResultCubit, ResultState>(
      listenWhen: (a, b) => (!a.openFailed && b.openFailed) || b.status == ResultStatus.opened,
      listener: (context, state) {
        if (state.status == ResultStatus.opened) {
          context.go('/');
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('result.openFailed'.tr())));
        }
      },
      builder: (context, state) {
        final result = state.result;
        final style = result == null ? null : VerdictStyle.of(result.verdict);
        final color = style?.color ?? Theme.of(context).colorScheme.primary;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave(context);
          },
          child: Scaffold(
            backgroundColor: result == null ? null : color,
            body: SafeArea(
              child: result == null
                  ? const _Checking()
                  : _Body(state: state, result: result, color: color, onLeave: () => _leave(context)),
            ),
          ),
        );
      },
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 6)),
          const SizedBox(height: 24),
          Text('result.checking'.tr(), style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.result,
    required this.color,
    required this.onLeave,
  });

  final ResultState state;
  final CheckResult result;
  final Color color;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ResultCubit>();
    final style = VerdictStyle.of(result.verdict);
    const fg = Colors.white;
    final uri = Uri.tryParse(result.url);
    final host = (uri == null || uri.host.isEmpty) ? result.url : uri.host;

    final titleKey = switch (result.verdict) {
      Verdict.safe => 'result.safe.title',
      Verdict.suspicious => 'result.suspicious.title',
      Verdict.dangerous => 'result.dangerous.title',
      Verdict.unchecked => 'result.unchecked.title',
    };

    final buttonTheme = Theme.of(context).copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.copyWith(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          foregroundColor: WidgetStatePropertyAll(color),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: theme.outlinedButtonTheme.style?.copyWith(
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          side: const WidgetStatePropertyAll(BorderSide(color: Colors.white, width: 2)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: theme.textButtonTheme.style?.copyWith(
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        ),
      ),
    );

    return Theme(
      data: buttonTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: fg),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Icon(style.icon, size: 112, color: fg)),
                    const SizedBox(height: 16),
                    Text(
                      titleKey.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      host,
                      style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.85)),
                    ),
                    if (result.finalUrl != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'result.goingTo'.tr(namedArgs: {'url': result.finalUrl!}),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ..._details(context, state, result, fg),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _Actions(state: state, result: result, onLeave: onLeave, cubit: cubit),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context, ResultState state, CheckResult result, Color fg) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(color: fg);
    switch (result.verdict) {
      case Verdict.safe:
        if (!state.counting) return const [];
        return [
          Text(
            'result.safe.opening'.tr(namedArgs: {
              'browser': state.browserLabel ?? 'result.browserChooser'.tr(),
              'seconds': '${state.secondsLeft}',
            }),
            style: body,
          ),
        ];
      case Verdict.suspicious:
        return [
          Text('result.suspicious.body'.tr(), style: body?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._reasonRows(result.reasons, body),
        ];
      case Verdict.unchecked:
        return [
          Text('result.unchecked.body'.tr(), style: body),
          const SizedBox(height: 8),
          ..._reasonRows(result.reasons, body),
        ];
      case Verdict.dangerous:
        final threats = result.threats.toSet();
        final descriptions = threats.isEmpty ? {ThreatType.unwantedSoftware} : threats;
        final social = threats.contains(ThreatType.socialEngineering);
        final link = theme.textTheme.bodyMedium?.copyWith(
          color: fg,
          decoration: TextDecoration.underline,
          decorationColor: fg,
        );
        final cubit = context.read<ResultCubit>();
        return [
          for (final t in descriptions) ...[
            Text('result.dangerous.${t.name}'.tr(), style: body),
            const SizedBox(height: 12),
          ],
          InkWell(
            onTap: () => cubit.openExternal(social ? _socialEngineeringHelpUrl : _malwareHelpUrl, navigateAfter: false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('result.learnMore'.tr(), style: link),
            ),
          ),
          Text('common.accuracyNotice'.tr(), style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          InkWell(
            onTap: () => cubit.openExternal(_advisoryUrl, navigateAfter: false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('result.google.attribution'.tr(), style: link),
            ),
          ),
        ];
    }
  }

  List<Widget> _reasonRows(List<ReasonCode> reasons, TextStyle? style) => [
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: Text('reason.${r.name}'.tr(), style: style)),
              ],
            ),
          ),
      ];
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.result,
    required this.onLeave,
    required this.cubit,
  });

  final ResultState state;
  final CheckResult result;
  final VoidCallback onLeave;
  final ResultCubit cubit;

  Future<void> _confirmOpen(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('result.confirmTitle'.tr()),
        content: Text('result.confirmBody'.tr(), style: Theme.of(ctx).textTheme.bodyLarge),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('result.confirmNo'.tr()),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 56),
              foregroundColor: VerdictStyle.of(Verdict.dangerous).color,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('result.confirmYes'.tr()),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.open();
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: result.url));
    messenger.showSnackBar(SnackBar(content: Text('result.copied'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    Widget gap() => const SizedBox(height: 12);
    final back = OutlinedButton(onPressed: onLeave, child: Text('result.back'.tr()));
    final recheck = FilledButton(onPressed: cubit.recheck, child: Text('result.recheck'.tr()));

    if (state.fromHistory) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          recheck,
          if (result.verdict == Verdict.dangerous) ...[
            gap(),
            OutlinedButton(onPressed: () => _copy(context), child: Text('result.copyLink'.tr())),
          ],
          gap(),
          back,
        ],
      );
    }

    switch (result.verdict) {
      case Verdict.safe:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: state.counting
              ? [
                  FilledButton(onPressed: cubit.open, child: Text('result.openNow'.tr())),
                  gap(),
                  OutlinedButton(onPressed: cubit.cancelCountdown, child: Text('result.cancel'.tr())),
                ]
              : [
                  FilledButton(onPressed: cubit.open, child: Text('result.open'.tr())),
                  gap(),
                  back,
                ],
        );
      case Verdict.suspicious:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(onPressed: onLeave, child: Text('result.dontOpen'.tr())),
            TextButton(onPressed: () => _confirmOpen(context), child: Text('result.openAnyway'.tr())),
          ],
        );
      case Verdict.unchecked:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(onPressed: cubit.recheck, child: Text('result.retry'.tr())),
            TextButton(onPressed: () => _confirmOpen(context), child: Text('result.openAnyway'.tr())),
          ],
        );
      case Verdict.dangerous:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(onPressed: onLeave, child: Text('result.back'.tr())),
            gap(),
            OutlinedButton(onPressed: () => _copy(context), child: Text('result.copyLink'.tr())),
          ],
        );
    }
  }
}
