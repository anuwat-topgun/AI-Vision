import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_vision/main.dart';

void main() {
  testWidgets('AC-004: File and Live tiles are both on Home', (tester) async {
    await tester.pumpWidget(const AiVisionApp());
    expect(find.byKey(const Key('tile_file')), findsOneWidget);
    expect(find.byKey(const Key('tile_live')), findsOneWidget);
  });
}
