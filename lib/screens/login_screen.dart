import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_sheet.dart';
import '../widgets/expressive.dart';

/// Shows the login form as a modal bottom sheet.
/// Returns true if login was successful.
Future<bool> showLoginDialog(BuildContext context) async {
  final result = await showAppSheet<bool>(
    context,
    builder: (ctx) => const _LoginSheet(),
  );
  return result == true;
}

class _LoginSheet extends StatefulWidget {
  const _LoginSheet();

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  /// Localization key of the current error, if any.
  String? _errorKey;
  late final TapGestureRecognizer _learnMoreRecognizer;

  @override
  void initState() {
    super.initState();
    _learnMoreRecognizer = TapGestureRecognizer()
      ..onTap = () {
        launchUrl(
          Uri.parse('https://github.com/MerrcuL/Uniwe#privacy-and-security'),
          mode: LaunchMode.externalApplication,
        );
      };
  }

  @override
  void dispose() {
    _learnMoreRecognizer.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    final user = _usernameController.text.trim();
    final pass = _passwordController.text;

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _errorKey = 'loginFieldsEmpty');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorKey = null;
    });

    final result = await context.read<AuthService>().login(user, pass);
    if (!mounted) return;

    switch (result) {
      case LoginResult.success:
        TextInput.finishAutofillContext();
        Navigator.of(context).pop(true);
      case LoginResult.invalidCredentials:
        setState(() {
          _isLoading = false;
          _errorKey = 'loginFailed';
        });
      case LoginResult.networkError:
        setState(() {
          _isLoading = false;
          _errorKey = 'loginNetworkError';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: ShapeBadge(icon: Icons.school_outlined, size: 72),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('loginTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.get('loginSubtitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.get('username'),
                    hintText: 's0000000',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.username],
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.get('password'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      tooltip: l10n.get(
                          _obscurePassword ? 'showPassword' : 'hidePassword'),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _handleLogin(),
                  enabled: !_isLoading,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: Durations.medium4,
            curve: Curves.easeInOutCubicEmphasized,
            alignment: Alignment.topCenter,
            child: _errorKey == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.get(_errorKey!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
            onPressed: _isLoading
                ? null
                : () {
                    HapticService.confirm(
                      context.read<SettingsService>().hapticsEnabled,
                    );
                    _handleLogin();
                  },
            child: _isLoading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(l10n.get('login')),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${l10n.get('loginStorageNote')} ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                TextSpan(
                  text: l10n.get('learnMore'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  recognizer: _learnMoreRecognizer,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
