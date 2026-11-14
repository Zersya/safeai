import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../checking/link_input.dart';
import '../../checking/models.dart';
import '../../core/theme.dart';
import '../result/result_cubit.dart';
import '../settings/settings_cubit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    setState(() {
      _controller.text = data!.text!;
      _error = false;
    });
  }

  void _check() {
    final url = extractUrl(_controller.text);
    if (url == null) {
      setState(() => _error = true);
      return;
    }
    setState(() => _error = false);
    context.push('/result', extra: ResultArgs(url: url, source: LinkSource.manual));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon/icon.png', width: 36, height: 36),
            const SizedBox(width: 12),
            const Text('blockAI'),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _ProtectionCard(),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              keyboardType: TextInputType.url,
              style: theme.textTheme.bodyLarge,
              onChanged: (_) {
                if (_error) setState(() => _error = false);
              },
              decoration: InputDecoration(
                hintText: 'home.hint'.tr(),
                errorText: _error ? 'home.notALink'.tr() : null,
                errorStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste, size: 28),
              label: Text('home.paste'.tr()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _check,
              icon: const Icon(Icons.search, size: 28),
              label: Text('home.check'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = context.watch<ProtectionCubit>().state;
    if (active == null) return const SizedBox(height: 96);
    final color = active ? VerdictStyle.of(Verdict.safe).color : VerdictStyle.of(Verdict.suspicious).color;
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(active ? Icons.verified_user : Icons.shield_outlined, color: Colors.white, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (active ? 'home.protection.activeTitle' : 'home.protection.inactiveTitle').tr(),
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (active ? 'home.protection.activeBody' : 'home.protection.inactiveBody').tr(),
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
            if (!active) ...[
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color),
                onPressed: () => context.read<ProtectionCubit>().request(),
                child: Text('home.protection.activate'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
