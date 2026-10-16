// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_training/main.dart';

void main() {
  testWidgets('Welcome screen displays editable sign-in fields', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Sign in / Login'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, 'test@example.com');
    await tester.enterText(find.byType(TextField).last, 'test-password');
    await tester.pump();

    expect(find.text('test@example.com'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });
}
