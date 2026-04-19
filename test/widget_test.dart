import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:uniwe/main.dart';
import 'package:uniwe/services/settings_service.dart';

void main() {
  testWidgets('HTW App foundational smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame with the necessary provider architecture.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: const UniweApp(),
      ),
    );

    // Allow all initial FutureBuilders and Settings configurations to resolve.
    await tester.pumpAndSettle();

    // Verify the root MaterialApp is constructed without breaking.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
