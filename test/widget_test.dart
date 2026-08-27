import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loopi_web/main.dart';
import 'package:loopi_web/widgets/app_logo.dart';
import 'package:loopi_web/widgets/save_routine_dialog.dart';

void main() {
  testWidgets('Social login is the initial screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LoopiApp());
    await tester.pump();

    expect(find.byType(AppLogo), findsWidgets);
    expect(find.text('유튜브 구간 반복 학습 루틴'), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('구글로 시작하기'), findsOneWidget);
    expect(find.text('애플로 시작하기'), findsOneWidget);
    expect(find.text('게스트로 둘러보기'), findsOneWidget);

    await tester.tap(find.text('게스트로 둘러보기'));
    await tester.pumpAndSettle();

    expect(find.text('새 루틴 만들기'), findsOneWidget);
    expect(find.text('최근 연습한 루틴'), findsOneWidget);
  });

  testWidgets('Save Routine dialog clears default name on first focus', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox.shrink()),
      ),
    );

    final future = showSaveRoutineDialog(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();

    expect(find.text('Save Routine Preset'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, defaultRoutineName());

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field.controller!.text, isEmpty);

    await tester.enterText(find.byType(TextField), 'Hip Hop Routine');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(await future, 'Hip Hop Routine');
  });
}
