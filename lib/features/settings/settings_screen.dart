import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'settings_cubit.dart';

const privacyPolicyUrl = 'https://zersya.github.io/blockai/privacy/';

const _idLocale = Locale('id', 'ID');
const _enLocale = Locale('en', 'US');

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsCubit>();
    final state = settings.state;
    final protection = context.watch<ProtectionCubit>().state;

    Widget header(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(
            key.tr(),
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: SafeArea(
        child: ListView(
          children: [
            header('settings.language'),
            RadioGroup<Locale>(
              groupValue: context.locale,
              onChanged: (l) {
                if (l != null) context.setLocale(l);
              },
              child: const Column(
                children: [
                  RadioListTile<Locale>(value: _idLocale, title: Text('Bahasa Indonesia')),
                  RadioListTile<Locale>(value: _enLocale, title: Text('English')),
                ],
              ),
            ),
            header('settings.browser'),
            RadioGroup<String>(
              groupValue: state.browserPackage ?? '',
              onChanged: (p) {
                if (p != null) settings.setBrowser(p.isEmpty ? null : p);
              },
              child: Column(
                children: [
                  RadioListTile<String>(value: '', title: Text('settings.browserAuto'.tr())),
                  for (final b in state.browsers)
                    RadioListTile<String>(value: b.package, title: Text(b.label)),
                ],
              ),
            ),
            header('settings.protection'),
            ListTile(
              leading: Icon(
                protection == true ? Icons.verified_user : Icons.shield_outlined,
                size: 36,
                color: protection == true ? theme.colorScheme.primary : theme.colorScheme.tertiary,
              ),
              title: Text(
                (protection == true ? 'settings.protectionActive' : 'settings.protectionInactive').tr(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: protection == true
                  ? OutlinedButton(
                      onPressed: context.read<ProtectionCubit>().openSettings,
                      child: Text('settings.defaultApps'.tr()),
                    )
                  : FilledButton(
                      onPressed: () => context.read<ProtectionCubit>().request(),
                      child: Text('settings.activate'.tr()),
                    ),
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, size: 32),
              title: Text('settings.guide'.tr()),
              onTap: () => context.push('/onboarding'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined, size: 32),
              title: Text('settings.privacy'.tr()),
              onTap: () => settings.openUrl(privacyPolicyUrl),
            ),
            header('settings.about'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('settings.version'.tr(namedArgs: {'version': state.version}), style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text('common.accuracyNotice'.tr(), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
