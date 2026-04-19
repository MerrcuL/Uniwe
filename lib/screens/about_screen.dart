import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import 'package:provider/provider.dart';

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
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  Future<void> _checkForUpdate() async {
    final settings = context.read<SettingsService>();
    HapticService.confirm(settings.hapticsEnabled);

    setState(() => _isCheckingUpdate = true);

    final updateInfo = await UpdateService.checkForUpdate();

    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    final l10n = AppLocalizations.of(context);

    if (updateInfo == null) {
      _showSnackBar(l10n.get('updateCheckFailed'), isError: true);
      return;
    }

    if (updateInfo.updateAvailable) {
      _showUpdateDialog(updateInfo);
    } else {
      _showSnackBar(l10n.get('upToDate'));
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError
                ? (theme.brightness == Brightness.light ? Colors.black : Colors.white)
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.system_update, color: theme.colorScheme.primary, size: 32),
        title: Text(l10n.get('updateAvailable')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.get('newVersion')}: ${updateInfo.latestVersion}',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.get('currentVersion')}: ${updateInfo.currentVersion}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (updateInfo.releaseBody.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    updateInfo.releaseBody,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.get('later')),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(
                Uri.parse(updateInfo.releaseUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l10n.get('download')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('about')),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 32),

          // App icon + name + version
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Uniwe',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.get('version')} $_appVersion',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.get('appDescription'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),

          // Check for updates
          ListTile(
            leading: _isCheckingUpdate
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Icon(Icons.system_update, color: theme.colorScheme.primary),
            title: Text(l10n.get('checkForUpdates')),
            subtitle: Text(
              l10n.get('checkForUpdatesSubtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            enabled: !_isCheckingUpdate,
            onTap: _checkForUpdate,
          ),

          const Divider(),

          // Source code link
          ListTile(
            leading: Icon(Icons.code, color: theme.colorScheme.primary),
            title: Text(l10n.get('sourceCode')),
            subtitle: Text(
              'github.com/MerrcuL/Uniwe',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () {
              HapticService.confirm(settings.hapticsEnabled);
              launchUrl(
                Uri.parse(UpdateService.repoUrl),
                mode: LaunchMode.externalApplication,
              );
            },
          ),

          const Divider(),

          // Licenses
          ListTile(
            leading: Icon(Icons.description_outlined, color: theme.colorScheme.primary),
            title: Text(l10n.get('licenses')),
            subtitle: Text(
              l10n.get('licensesSubtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              HapticService.confirm(settings.hapticsEnabled);
              showLicensePage(
                context: context,
                applicationName: 'Uniwe',
                applicationVersion: _appVersion,
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      size: 36,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              );
            },
          ),

          const Divider(),

          // Acknowledgements section
          _buildSectionHeader(context, l10n.get('acknowledgements')),
          _buildAcknowledgementItem(
            context,
            'Flutter',
            l10n.get('flutterDesc'),
            'https://flutter.dev',
          ),
          _buildAcknowledgementItem(
            context,
            'OpenMensa API',
            l10n.get('openMensaDesc'),
            'https://openmensa.org',
          ),
          _buildAcknowledgementItem(
            context,
            'enough_mail',
            l10n.get('enoughMailDesc'),
            'https://pub.dev/packages/enough_mail',
          ),
          _buildAcknowledgementItem(
            context,
            'BVG Transport API',
            l10n.get('bvgApiDesc'),
            'https://v6.bvg.transport.rest',
          ),

          const SizedBox(height: 32),

          // Footer
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.get('madeWithLove'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildAcknowledgementItem(
    BuildContext context,
    String name,
    String description,
    String url,
  ) {
    final theme = Theme.of(context);
    final settings = context.read<SettingsService>();

    return ListTile(
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        description,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.open_in_new, size: 16),
      dense: true,
      onTap: () {
        HapticService.confirm(settings.hapticsEnabled);
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
    );
  }
}
