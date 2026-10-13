import 'package:embyplayer/src/app/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    SpatialAmbientController.instance.update(
      itemId: null,
      imageUri: null,
      paletteSeed: 0,
      dominantColor: null,
    );
    SpatialAmbientController.instance.setTheme(SpatialBackdropTheme.spatialFlow);
    SpatialAmbientController.instance.setTheaterBlackout(false);
  });

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

  test('SpatialAmbientController updates theme, blackout, and dominantColor', () {
    final controller = SpatialAmbientController.instance;
    expect(controller.value.theme, SpatialBackdropTheme.spatialFlow);
    expect(controller.value.theaterBlackout, isFalse);

    controller.setTheme(SpatialBackdropTheme.cyberpunk);
    expect(controller.value.theme, SpatialBackdropTheme.cyberpunk);

    controller.setTheaterBlackout(true);
    expect(controller.value.theaterBlackout, isTrue);

    controller.update(
      itemId: 'movie-101',
      paletteSeed: 42,
      dominantColor: const Color(0xFF6B421B),
    );
    expect(controller.value.itemId, 'movie-101');
    expect(controller.value.paletteSeed, 42);
    expect(controller.value.dominantColor, const Color(0xFF6B421B));
    expect(controller.value.theme, SpatialBackdropTheme.cyberpunk);
    expect(controller.value.theaterBlackout, isTrue);
  });

  testWidgets('AmbientBackdrop renders child and reflects theme changes', (
    tester,
  ) async {
    SpatialAmbientController.instance.setTheme(SpatialBackdropTheme.deepNebula);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientBackdrop(
            child: Text('Living Cinema Canvas'),
          ),
        ),
      ),
    );

    expect(find.text('Living Cinema Canvas'), findsOneWidget);
    expect(find.byType(AmbientBackdrop), findsOneWidget);

    // Switch to pure OLED mode
    SpatialAmbientController.instance.setTheme(SpatialBackdropTheme.pureOled);
    await tester.pumpAndSettle();
    expect(find.text('Living Cinema Canvas'), findsOneWidget);

    // Switch to Theater blackout
    SpatialAmbientController.instance.setTheaterBlackout(true);
    await tester.pumpAndSettle();
    expect(find.text('Living Cinema Canvas'), findsOneWidget);
  });

  testWidgets('Nested AmbientBackdrop delegates to child without duplicate backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientBackdrop(
            child: AmbientBackdrop(
              child: Text('Nested Content'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Nested Content'), findsOneWidget);
  });
}
