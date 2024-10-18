// logger.dart

import 'package:flutter/foundation.dart'; // For kDebugMode

class Logger {
  static void log(String message) {
    if (kDebugMode) {
      print(message);
    }
  }
}
