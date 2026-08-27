import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loopi_web/main.dart';
import 'package:loopi_web/models/routine_models.dart';
import 'package:loopi_web/state/routine_library.dart';
import 'package:loopi_web/widgets/app_logo.dart';
import 'package:loopi_web/widgets/save_routine_dialog.dart';

void main() {
  testWidgets('Social login is the initial screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('ko'),
        child: const LoopiApp(),
      ),
    );
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

  test('Routine library creates and persists groups with ordered routine ids', () async {
    SharedPreferences.setMockInitialValues({});
    final library = RoutineLibrary();
    await library.load();

    final r1 = SavedRoutine(
      id: 'r1',
      name: 'Warm Up',
      videoUrl: 'https://youtube.com/watch?v=aaa',
      videoId: 'aaa',
      segments: const [
        RoutineSegment(
          id: 's1',
          startSec: 0,
          endSec: 10,
          speed: 1,
          loopCount: 1,
          delaySec: 1,
        ),
      ],
      createdAt: DateTime.now(),
    );
    final r2 = SavedRoutine(
      id: 'r2',
      name: 'Stretch',
      videoUrl: 'https://youtube.com/watch?v=bbb',
      videoId: 'bbb',
      segments: const [
        RoutineSegment(
          id: 's2',
          startSec: 0,
          endSec: 15,
          speed: 1,
          loopCount: 1,
          delaySec: 2,
        ),
      ],
      createdAt: DateTime.now(),
    );

    library.save(r1);
    library.save(r2);
    await library.createGroup(name: 'Mobility', routineIds: [r1.id, r2.id]);

    expect(library.groups, hasLength(1));
    expect(library.groups.first.title, 'Mobility');
    expect(library.groups.first.routineIds, [r1.id, r2.id]);
    expect(library.routinesForGroup(library.groups.first), hasLength(2));

    final reloaded = RoutineLibrary();
    await reloaded.load();
    expect(reloaded.groups, hasLength(1));
    expect(reloaded.groups.first.title, 'Mobility');
    expect(reloaded.routinesForGroup(reloaded.groups.first).map((e) => e.id), [r1.id, r2.id]);
  });
}
