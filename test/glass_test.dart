import 'package:embyplayer/src/app/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders VisionGlassCapsuleIsland and VisionGlassBadge correctly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VisionGlassCapsuleIsland(
                child: VisionGlassBadge(label: '4K HDR', icon: Icons.hd),
              ),
            ),
          ),
        ),
      );

      expect(find.text('4K HDR'), findsOneWidget);
      expect(find.byIcon(Icons.hd), findsOneWidget);
      expect(find.byType(VisionGlassCapsuleIsland), findsOneWidget);
    },
  );
}
