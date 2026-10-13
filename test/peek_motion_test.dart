import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses PEeK shared-axis transitions for Windows routes', () {
    final builder =
        AppTheme.dark().pageTransitionsTheme.builders[TargetPlatform.windows];

    expect(builder, isA<PeekPageTransitionsBuilder>());
  });

  testWidgets('keeps destination state while switching pages', (tester) async {
    var selectedIndex = 0;
    late void Function(int index) select;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) {
            select = (index) => setState(() => selectedIndex = index);
            return SizedBox(
              width: 800,
              height: 600,
              child: PeekIndexedTransitionStack(
                index: selectedIndex,
                children: const [
                  _CounterPage(),
                  Center(child: Text('第二页')),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('counter-button')));
    await tester.pump();
    expect(find.text('次数 1'), findsOneWidget);
    expect(find.byType(Transform), findsWidgets);

    select(1);
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    select(0);
    await tester.pumpAndSettle();
    expect(find.text('次数 1'), findsOneWidget);
  });

  testWidgets('honors reduced motion for destination transitions', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PeekIndexedTransitionStack(
          index: 0,
          children: const [Text('第一页'), Text('第二页')],
        ),
      ),
    );

    final offstages = tester.widgetList<Offstage>(find.byType(Offstage));
    expect(offstages, isNotEmpty);
    expect(find.text('第一页'), findsOneWidget);
  });
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        key: const ValueKey('counter-button'),
        onPressed: () => setState(() => _count += 1),
        child: Text('次数 $_count'),
      ),
    );
  }
}
