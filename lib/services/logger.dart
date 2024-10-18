// logger.dart

import 'package:flutter/foundation.dart';

class Logger {
  static void log(String message) {
    if (kDebugMode) {
      print(message);
    }
  }
}
