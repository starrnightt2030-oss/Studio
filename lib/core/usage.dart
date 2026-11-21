import 'package:flutter/foundation.dart';

import 'storage/local_db.dart';

/// عداد الاستهلاك: طلبات Gemini النهارده، وحروف Azure الشهر ده.
class Usage {
  Usage._();

  static final changes = ValueNotifier<int>(0);

  static String get _day => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  static String get _month => _day.substring(0, 7);

  static const azureMonthlyFree = 500000;

  static int get geminiRequestsToday => (LocalDb.settings.get('usage:g:$_day', defaultValue: 0) as int);
  static int get geminiCharsToday => (LocalDb.settings.get('usage:gc:$_day', defaultValue: 0) as int);
  static int get azureCharsMonth => (LocalDb.settings.get('usage:a:$_month', defaultValue: 0) as int);
  static int get textRequestsToday => (LocalDb.settings.get('usage:t:$_day', defaultValue: 0) as int);

  static Future<void> gemini(int chars) async {
    await LocalDb.settings.put('usage:g:$_day', geminiRequestsToday + 1);
    await LocalDb.settings.put('usage:gc:$_day', geminiCharsToday + chars);
    changes.value++;
  }

  static Future<void> azure(int chars) async {
    await LocalDb.settings.put('usage:a:$_month', azureCharsMonth + chars);
    changes.value++;
  }

  static Future<void> text() async {
    await LocalDb.settings.put('usage:t:$_day', textRequestsToday + 1);
    changes.value++;
  }
}
