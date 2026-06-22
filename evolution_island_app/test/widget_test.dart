// Basic smoke test for 达尔文进化岛.

import 'package:evolution_island/game_screen.dart';
import 'package:evolution_island/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the start screen and can begin the game', (tester) async {
    await tester.pumpWidget(const EvolutionIslandApp());

    // The start screen with the title and the play button is visible.
    expect(find.text('达尔文进化岛'), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);

    // The game itself is mounted.
    expect(find.byType(EvolutionIslandGame), findsOneWidget);

    // Tapping "开始游戏" dismisses the start overlay.
    await tester.tap(find.text('开始游戏'));
    await tester.pump();
    expect(find.text('开始游戏'), findsNothing);
  });
}
