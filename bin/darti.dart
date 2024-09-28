import 'package:darti/darti.dart';

void main(List<String> arguments) {
  Darti.main('fac(n) => n == 0 ? 1 : fac(n - 1) * n; main() { print(fac(5)); }', arguments);
}
