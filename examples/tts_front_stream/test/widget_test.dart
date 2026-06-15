import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_tts_front/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const TTSApp());
    expect(find.text('TheStage AI SDK'), findsOneWidget);
  });
}
