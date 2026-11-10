import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';
import '../widgets/update_dialog.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _appVersion = '';
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = packageInfo.version);
    } catch (_) {
      // Version stays blank if the platform cannot report it.
    }
  }

  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);

    setState(() => _isCheckingUpdate = true);
    final updateInfo = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    final l10n = AppLocalizations.of(context);
    if (updateInfo == null) {
      _showSnackBar(l10n.get('updateCheckFailed'));
    } else if (updateInfo.updateAvailable) {
      showUpdateDialog(context, updateInfo);
    } else {
      _showSnackBar(l10n.get('upToDate'));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(String url) {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gutter = AppSpacing.gutter(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('about'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            gutter, 16, gutter, AppSpacing.bottomInset(context, spacing: 32)),
        children: [
          // App icon + name + version
          Column(
            children: [
              const ShapeBadge(
                icon: Icons.school_rounded,
                size: 112,
                shape: SoftShape.sunny,
              ),
              const SizedBox(height: 16),
              Text('Uniwe', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                '${l10n.get('version')} $_appVersion',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.get('appDescription'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: 24),

          ListGroup(
            children: [
              ListTile(
                leading: _isCheckingUpdate
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.system_update_rounded),
                title: Text(l10n.get('checkForUpdates')),
                subtitle: Text(l10n.get('checkForUpdatesSubtitle')),
                enabled: !_isCheckingUpdate,
                onTap: _checkForUpdate,
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: Text(l10n.get('sourceCode')),
                subtitle: const Text('github.com/MerrcuL/Uniwe'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => _open(UpdateService.repoUrl),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(l10n.get('licenses')),
                subtitle: Text(l10n.get('licensesSubtitle')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  HapticService.confirm(
                    context.read<SettingsService>().hapticsEnabled,
                  );
                  showLicensePage(
                    context: context,
                    applicationName: 'Uniwe',
                    applicationVersion: _appVersion,
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(16),
                      child: ShapeBadge(
                        icon: Icons.school_rounded,
                        size: 72,
                        shape: SoftShape.sunny,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          SectionHeader(l10n.get('acknowledgements')),
          ListGroup(
            children: [
              _acknowledgement(
                'Flutter',
                l10n.get('flutterDesc'),
                'https://flutter.dev',
              ),
              _acknowledgement(
                'OpenMensa API',
                l10n.get('openMensaDesc'),
                'https://openmensa.org',
              ),
              _acknowledgement(
                'enough_mail',
                l10n.get('enoughMailDesc'),
                'https://pub.dev/packages/enough_mail',
              ),
              _acknowledgement(
                'BVG Transport API',
                l10n.get('bvgApiDesc'),
                'https://v6.bvg.transport.rest',
              ),
            ],
          ),

          const SizedBox(height: 32),
          Text(
            l10n.get('madeWithLove'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _acknowledgement(String name, String description, String url) {
    return ListTile(
      title: Text(name),
      subtitle: Text(description),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: () => _open(url),
    );
  }
}
