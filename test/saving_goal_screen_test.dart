import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/screens/management/saving_goal_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('SavingGoal Model Tests', () {
    test('1. Parsed successfully with standard String date and num amounts', () {
      final now = DateTime(2026, 10, 11, 10, 0, 0);
      final map = {
        'userId': 'user_123',
        'name': 'Laptop Dell XPS',
        'targetAmount': 30000000,
        'savedAmount': 15000000,
        'months': 6,
        'createdAt': now.toIso8601String(),
      };

      final goal = SavingGoal.fromMap(map, 'goal_1');
      expect(goal.goalId, 'goal_1');
      expect(goal.userId, 'user_123');
      expect(goal.name, 'Laptop Dell XPS');
      expect(goal.targetAmount, 30000000.0);
      expect(goal.savedAmount, 15000000.0);
      expect(goal.months, 6);
      expect(goal.percentComplete, 0.5);
      expect(goal.monthlyRequired, 2500000.0);
      expect(goal.dailyRequired, closeTo(83333.33, 0.1));
    });

    test('2. Parsed successfully when createdAt is Firestore Timestamp', () {
      final ts = Timestamp.fromDate(DateTime(2026, 5, 20, 8, 30));
      final map = {
        'userId': 'user_456',
        'name': 'Du lịch Nhật Bản',
        'targetAmount': 20000000.0,
        'savedAmount': 5000000.0,
        'months': 10,
        'createdAt': ts,
      };

      final goal = SavingGoal.fromMap(map, 'goal_2');
      expect(goal.name, 'Du lịch Nhật Bản');
      expect(goal.createdAt.year, 2026);
      expect(goal.createdAt.month, 5);
      expect(goal.createdAt.day, 20);
    });

    test('3. Resilient against String numbers and missing fields', () {
      final map = {
        'userId': 'user_789',
        'name': 'Quỹ khẩn cấp',
        'targetAmount': '50000000',
        'savedAmount': '20000000',
        'months': '12',
        'createdAt': null,
      };

      final goal = SavingGoal.fromMap(map, 'goal_3');
      expect(goal.targetAmount, 50000000.0);
      expect(goal.savedAmount, 20000000.0);
      expect(goal.months, 12);
      expect(goal.percentComplete, 0.4);
    });

    test('4. Correctly handles completed goal without negative monthly requirements', () {
      final map = {
        'userId': 'user_999',
        'name': 'Mua sách',
        'targetAmount': 1000000.0,
        'savedAmount': 1500000.0, // Đã tiết kiệm vượt mục tiêu
        'months': 2,
      };

      final goal = SavingGoal.fromMap(map, 'goal_4');
      expect(goal.percentComplete, 1.0);
      expect(goal.monthlyRequired, 0.0);
      expect(goal.dailyRequired, 0.0);
    });

    test('5. SavingGoalDurationHelper calculates clamped dates and custom month/year durations accurately', () {
      expect(
        SavingGoalDurationHelper.addMonthsClamped(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        SavingGoalDurationHelper.addMonthsClamped(DateTime(2026, 11, 16), 18),
        DateTime(2028, 5, 16),
      );
      expect(
        SavingGoalDurationHelper.monthsBetweenForTargetDate(
          DateTime(2026, 11, 16),
          DateTime(2028, 5, 16),
        ),
        18,
      );
      expect(
        SavingGoalDurationHelper.monthsBetweenForTargetDate(
          DateTime(2026, 11, 16),
          DateTime(2026, 11, 20),
        ),
        1,
      );
      expect(
        SavingGoalDurationHelper.monthsBetweenForTargetDate(
          DateTime(2026, 11, 16),
          DateTime(2070, 1, 1),
        ),
        SavingGoalDurationHelper.maxMonths,
      );
    });

    testWidgets('6. OutlinedButton in Row with app theme does not throw infinite width constraint exception', (tester) async {
      final theme = ThemeData(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 48),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: Text('Summary')),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: const Text('Pick date'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Pick date'), findsOneWidget);
    });
  });
}
