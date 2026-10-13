import 'package:embyplayer/src/core/presentation/peek_3d_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Peek3DCard renders and responds to hover gesture', (
    tester,
  ) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: Peek3DCard(
                onTap: () => tapped = true,
                child: const Text('3D Card Test'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('3D Card Test'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('3D Card Test')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3D Card Test'));
    expect(tapped, isTrue);
  });
}
