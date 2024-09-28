import 'dart:io';
import 'dart:math';

import 'package:darti/darti.dart';

void main() {
  Darti.global.bindings
    ..['Random'] = DartiFunction((_) => Random())
    ..['stdin'] = stdin
    ..['int'] = int;
  Darti.main(File('example/hammurabi.dart').readAsStringSync());
}
