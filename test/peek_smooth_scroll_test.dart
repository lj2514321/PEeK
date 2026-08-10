import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PeekSmoothScroll renders child without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PeekSmoothScroll(
            child: Text('Smooth Scroll Child'),
          ),
        ),
      ),
    );

    expect(find.text('Smooth Scroll Child'), findsOneWidget);
  });
}
