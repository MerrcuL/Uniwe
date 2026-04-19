import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String releaseName;
  final String releaseBody;
  final bool updateAvailable;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    required this.releaseName,
    required this.releaseBody,
    required this.updateAvailable,
  });
}

class UpdateService {
  static const String _owner = 'MerrcuL';
  static const String _repo = 'Uniwe';
  static const String _apiUrl = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';
  static const String repoUrl = 'https://github.com/$_owner/$_repo';

  /// Checks the latest GitHub release and compares it with the current app version.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final releaseBody = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '$repoUrl/releases/latest';

      // Strip 'v' prefix if present for comparison
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final isNewer = _isVersionNewer(latestVersion, currentVersion);

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        releaseUrl: htmlUrl,
        releaseName: releaseName,
        releaseBody: releaseBody,
        updateAvailable: isNewer,
      );
    } catch (_) {
      return null;
    }
  }

  /// Simple semantic version comparison: returns true if [latest] > [current].
  static bool _isVersionNewer(String latest, String current) {
    final latestParts = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final currentParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad to same length
    while (latestParts.length < 3) {
      latestParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }
}
