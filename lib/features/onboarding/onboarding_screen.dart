import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../data/settings_repository.dart';
import '../settings/settings_cubit.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _lastPage = 2;
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  Future<void> _finish() async {
    final router = GoRouter.of(context);
    await context.read<SettingsRepository>().setOnboardingDone(true);
    router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (p) => setState(() => _page = p),
                children: const [_WelcomePage(), _HowPage(), _ProtectPage()],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i <= _lastPage; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(6),
                    width: i == _page ? 28 : 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: _page == _lastPage
                  ? FilledButton(onPressed: _finish, child: Text('onboarding.start'.tr()))
                  : Column(
                      children: [
                        FilledButton(
                          onPressed: () => _goTo(_page + 1),
                          child: Text('onboarding.next'.tr()),
                        ),
                        TextButton(
                          onPressed: () => _goTo(_lastPage),
                          child: Text('onboarding.skip'.tr()),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isId = context.locale.languageCode == 'id';
    return _PageFrame(
      children: [
        const SizedBox(height: 16),
        Center(child: Image.asset('assets/icon/icon.png', width: 140, height: 140)),
        const SizedBox(height: 24),
        Text(
          'onboarding.welcome.title'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text('onboarding.welcome.body'.tr(), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 32),
        Text('onboarding.welcome.language'.tr(), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        _LanguageButton(label: 'Bahasa Indonesia', locale: const Locale('id', 'ID'), selected: isId),
        const SizedBox(height: 12),
        _LanguageButton(label: 'English', locale: const Locale('en', 'US'), selected: !isId),
      ],
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.label, required this.locale, required this.selected});

  final String label;
  final Locale locale;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    void onPressed() => context.setLocale(locale);
    return selected
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

class _HowPage extends StatelessWidget {
  const _HowPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(IconData icon, String key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, size: 36, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(key.tr(), style: theme.textTheme.bodyLarge)),
            ],
          ),
        );
    return _PageFrame(
      children: [
        const SizedBox(height: 16),
        Text(
          'onboarding.how.title'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        step(Icons.touch_app, 'onboarding.how.step1'),
        step(Icons.manage_search, 'onboarding.how.step2'),
        step(Icons.verified_user, 'onboarding.how.step3'),
      ],
    );
  }
}

class _ProtectPage extends StatefulWidget {
  const _ProtectPage();

  @override
  State<_ProtectPage> createState() => _ProtectPageState();
}

class _ProtectPageState extends State<_ProtectPage> {
  bool _failed = false;

  Future<void> _activate() async {
    final granted = await context.read<ProtectionCubit>().request();
    if (mounted) setState(() => _failed = !granted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = context.watch<ProtectionCubit>().state == true;
    return _PageFrame(
      children: [
        const SizedBox(height: 16),
        Icon(Icons.shield, size: 96, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'onboarding.protect.title'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text('onboarding.protect.body'.tr(), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (active)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 36),
              const SizedBox(width: 8),
              Text(
                'onboarding.protect.active'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          )
        else ...[
          FilledButton(onPressed: _activate, child: Text('onboarding.protect.button'.tr())),
          if (_failed) ...[
            const SizedBox(height: 16),
            Text('onboarding.protect.failed'.tr(), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: context.read<ProtectionCubit>().openSettings,
              child: Text('onboarding.protect.openSettings'.tr()),
            ),
          ],
        ],
        const SizedBox(height: 32),
        Text('common.accuracyNotice'.tr(), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text('onboarding.protect.google'.tr(), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
