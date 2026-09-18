import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/main.dart';

void main() {
  testWidgets('shows the login page when no camera is available', (
    WidgetTester tester,
  ) async {
    cameras = [];

    await tester.pumpWidget(const BurnAssessmentApp());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
