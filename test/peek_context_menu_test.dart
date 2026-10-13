import 'package:embyplayer/src/core/presentation/peek_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows context menu on secondary tap (right click)', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PeekContextMenuRegion(
              items: (context) => [
                PeekContextMenuItem(
                  id: 'action',
                  label: '测试菜单项',
                  icon: Icons.play_arrow,
                  onTap: () {
                    tapped = true;
                  },
                ),
              ],
              child: Container(
                width: 100,
                height: 100,
                color: Colors.blue,
                key: const ValueKey('target'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('测试菜单项'), findsNothing);

    // Perform right click (secondary tap)
    await tester.tap(
      find.byKey(const ValueKey('target')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('测试菜单项'), findsOneWidget);

    await tester.tap(find.text('测试菜单项'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
