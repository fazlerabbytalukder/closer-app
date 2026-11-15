import 'package:closer_app/core/data/closer_backend.dart';
import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/features/plan/date_planner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Countdown _event({
  required DateTime date,
  DateTime? end,
  bool yearly = false,
  bool hasTime = true,
  EventCategory category = EventCategory.other,
  bool done = false,
}) =>
    Countdown(
      id: 'e${date.millisecondsSinceEpoch}',
      title: 'Event',
      date: date,
      endDate: end,
      repeatsYearly: yearly,
      hasTime: hasTime,
      category: category,
      done: done,
      createdBy: 'a',
    );

void main() {
  group('Calendar events (merged countdowns)', () {
    test('old countdown docs parse as countdowns in the "other" category', () {
      final c = Countdown.fromJson('c', {'title': 'Paris', 'date': DateTime(2026, 12, 1).millisecondsSinceEpoch});
      expect(c.showAsCountdown, isTrue);
      expect(c.category, EventCategory.other);
      expect(c.ratings, isEmpty);
    });

    test('new fields round-trip', () {
      final e = Countdown(
        id: 'x',
        title: 'Dinner',
        date: DateTime(2026, 11, 20, 19),
        hasTime: true,
        category: EventCategory.date,
        isVirtual: true,
        place: 'Zoom',
        note: 'Dress up',
        showAsCountdown: false,
        ratings: const {'a': 5},
        done: true,
        createdBy: 'a',
      );
      final back = Countdown.fromJson('x', e.toJson());
      expect(back.category, EventCategory.date);
      expect(back.isVirtual, isTrue);
      expect(back.place, 'Zoom');
      expect(back.showAsCountdown, isFalse);
      expect(back.ratings['a'], 5);
      expect(back.done, isTrue);
    });

    test('multi-day events cover every day of the range', () {
      final trip = _event(date: DateTime(2026, 12, 20), end: DateTime(2026, 12, 23), hasTime: false);
      expect(trip.occursOn(DateTime(2026, 12, 19)), isFalse);
      expect(trip.occursOn(DateTime(2026, 12, 20)), isTrue);
      expect(trip.occursOn(DateTime(2026, 12, 22, 15)), isTrue);
      expect(trip.occursOn(DateTime(2026, 12, 24)), isFalse);
      expect(trip.isPast(DateTime(2026, 12, 23, 12)), isFalse);
      expect(trip.isPast(DateTime(2026, 12, 24)), isTrue);
    });

    test('yearly events repeat on the same day, never before they began', () {
      final bday = _event(date: DateTime(2020, 3, 14), yearly: true, hasTime: false);
      expect(bday.occursOn(DateTime(2027, 3, 14)), isTrue);
      expect(bday.occursOn(DateTime(2019, 3, 14)), isFalse);
      expect(bday.isPast(DateTime(2030)), isFalse);
    });

    test('checkEvent rejects ranges that end before they start', () {
      expect(
        () => checkEvent(_event(date: DateTime(2026, 5, 10), end: DateTime(2026, 5, 9))),
        throwsA(isA<CloserException>()),
      );
    });
  });

  group('Date goal', () {
    final now = DateTime(2026, 11, 18, 12); // a Wednesday

    test('weekly periods start on Monday', () {
      const g = DateGoal(count: 1);
      expect(g.periodStart(now), DateTime(2026, 11, 16));
      expect(g.periodEnd(now), DateTime(2026, 11, 23));
      expect(g.label, '1 date a week');
    });

    test('monthly periods start on the 1st', () {
      const g = DateGoal(count: 2, perMonth: true);
      expect(g.periodStart(now), DateTime(2026, 11));
      expect(g.previousStart(DateTime(2026, 1)), DateTime(2025, 12));
      expect(DateGoal.fromJson(g.toJson()).perMonth, isTrue);
    });

    test('streak counts consecutive weeks that hit the goal', () {
      const g = DateGoal(count: 1);
      final events = [
        _event(date: DateTime(2026, 11, 17, 19), category: EventCategory.date), // this week, already happened
        _event(date: DateTime(2026, 11, 12, 19), category: EventCategory.date), // last week
        _event(date: DateTime(2026, 11, 4, 19), category: EventCategory.date), // the week before
        _event(date: DateTime(2026, 10, 20, 19), category: EventCategory.date), // gap before this
        _event(date: DateTime(2026, 11, 11, 19)), // not a date
      ];
      expect(datesBetween(events, g.periodStart(now), g.periodEnd(now), now), 1);
      expect(goalStreak(events, g, now), 3);
    });
  });

  group('To-dos', () {
    test('round-trip, assignment and overdue', () {
      final t = Todo(id: 't', listId: 'l', text: 'Book table', assignee: 'b', due: DateTime(2026, 11, 10), createdBy: 'a');
      final back = Todo.fromJson('t', t.toJson());
      expect(back.isFor('b'), isTrue);
      expect(back.isFor('a'), isFalse);
      expect(const Todo(id: 't', listId: 'l', text: 'x', createdBy: 'a').isFor('a'), isTrue);
      expect(back.isOverdue(DateTime(2026, 11, 11)), isTrue);
      expect(back.isOverdue(DateTime(2026, 11, 10, 23)), isFalse);
      expect(() => checkTodo(const Todo(id: '', listId: 'l', text: '  ', createdBy: 'a')), throwsA(isA<CloserException>()));
    });
  });

  group('Wishes', () {
    test('round-trip and categories', () {
      const w = Wish(id: 'w', title: 'Socks', category: WishCategory.gift, ownerUid: 'a', price: '€12', createdBy: 'a');
      final back = Wish.fromJson('w', w.toJson());
      expect(back.isGift, isTrue);
      expect(back.ownerUid, 'a');
      expect(WishCategory.parse('nope'), WishCategory.other);
      expect(() => checkWish(const Wish(id: '', title: '', createdBy: 'a')), throwsA(isA<CloserException>()));
    });
  });
}
