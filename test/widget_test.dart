import 'package:flutter_test/flutter_test.dart';
import 'package:android_ai_gateway/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AndroidAIGatewayApp(cameras: []));
    expect(find.byType(AndroidAIGatewayApp), findsOneWidget);
  });
}
