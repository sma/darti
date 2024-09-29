import 'dart:async';

import 'package:darti/darti.dart';
import 'package:test/test.dart';

/// Runs [source] and returns everything output by `print`.
/// Exceptions that occur while running are printed and rethrown.
String run(String source) {
  final output = StringBuffer();
  runZoned(
    () => Darti.main(source),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        output.writeln(line);
      },
      handleUncaughtError: (self, parent, zone, error, stackTrace) {
        print(error);
        print(stackTrace);
        throw error;
      },
    ),
  );
  return output.toString();
}

/// Evaluates [source] as a single expression and returns the result
/// as a string. Exceptions that occur while evaluating are rethrown.
String eval(String source) {
  return run('main() { print($source); }').trim();
}

void main() {
  final throwsDartiException = throwsA(isA<DartiException>());

  group('base', () {
    test('empty main', () {
      expect(run('main() {}'), '');
    });
    test('hello world', () {
      expect(run('main() { print("Hello, World!"); }'), 'Hello, World!\n');
    });
    test('missing main', () {
      expect(() => run('foo() {}'), throwsArgumentError);
    });
    test('syntax error', () {
      expect(() => run('main() {'), throwsArgumentError);
    });
  });

  group('expressions', () {
    group('literals', () {
      test('null', () {
        expect(eval('null'), 'null');
      });
      test('booleans', () {
        expect(eval('true'), 'true');
        expect(eval('false'), 'false');
      });
      test('integers', () {
        expect(eval('0'), '0');
        expect(eval('13'), '13');
        expect(eval('-42'), '-42');
      });
      test('doubles', () {
        expect(eval('0.0'), '0.0');
        expect(eval('1.3'), '1.3');
        expect(eval('-4.2'), '-4.2');
      });
      test('strings', () {
        expect(eval('""'), '');
        expect(eval('"abc"'), 'abc');
        expect(eval('"""abc"""'), 'abc');
      });
      test('lists', () {
        expect(eval('[]'), '[]');
        expect(eval('[null, true, 42, "abc"]'), '[null, true, 42, abc]');
        expect(eval('[...[1]]'), '[1]');
        expect(eval('[...?[1], ...?null, 2]'), '[1, 2]');
        expect(eval('[?null, ?2]'), '[2]');
        expect(eval('[1, if (true) 2 else ...[3]]'), '[1, 2]');
        expect(eval('[1, if (false) 2 else ...[3]]'), '[1, 3]');
      });

      test('maps', () {
        expect(eval('{}'), '{}');
        expect(eval('{"a": 1, "b": true}'), '{a: 1, b: true}');
        expect(eval('{...{"a": 1}}'), '{a: 1}');
        expect(eval('{...?{"a": 1}, ?null, "b": false}'), '{a: 1, b: false}');
        expect(eval('{?null, ?"a": 2}'), '{a: 2}');
        expect(eval('{"a": 1, if (true) "b": 2 else ...{"c": 3}}'), '{a: 1, b: 2}');
        expect(eval('{"a": 1, if (false) "b": 2 else ...{"c": 3}}'), '{a: 1, c: 3}');
      });

      test('sets', () {
        expect(eval('{1, 2}'), '{1, 2}');
      });
    });

    test('string interpolation', () {
      expect(eval('"a\${42}B"'), 'a42B');
    });

    group('arithmetic', () {
      test('+', () {
        expect(eval('1+2'), '3');
        expect(eval('1.0+2'), '3.0');
        expect(eval('1+2.0'), '3.0');
        expect(eval('1.5+2.5'), '4.0');
        expect(eval('1.5+2.5'), '4.0');
        expect(eval('"a" + "b"'), 'ab');
      });
      test('*', () {
        expect(eval('2*3'), '6');
        expect(eval('2.0*3'), '6.0');
        expect(eval('2*3.0'), '6.0');
        expect(eval('2.0*3.5'), '7.0');
        expect(eval('"a" * 3'), 'aaa');
      });
      test('-', () {
        expect(eval('3-4'), '-1');
        expect(eval('3.0-4'), '-1.0');
        expect(eval('3-4.0'), '-1.0');
        expect(eval('3.0-4.5'), '-1.5');
      });
      test('/', () {
        expect(eval('7 / 2'), '3.5');
        expect(eval('7.0 / 2'), '3.5');
        expect(eval('7 / 2.0'), '3.5');
        expect(eval('7.0 / 2.0'), '3.5');
      });
      test('~/', () {
        expect(eval('7 ~/ 2'), '3');
        expect(eval('7.0 ~/ 2'), '3');
        expect(eval('7 ~/ 2.0'), '3');
        expect(eval('7.0 ~/ 2.0'), '3');
      });
      test('%', () {
        expect(eval('7 % 2'), '1');
        expect(eval('7.0 % 2'), '1.0');
        expect(eval('7 % 2.0'), '1.0');
        expect(eval('7.5 % 2.0'), '1.5');
      });
    });

    group('comparisons', () {
      test('==', () {
        expect(eval('1 == 2'), 'false');
        expect(eval('2.0 == 2'), 'true');
      });
      test('!=', () {
        expect(eval('1 != 2'), 'true');
        expect(eval('2.0 != 2'), 'false');
      });
      test('<', () {
        expect(eval('1 < 2'), 'true');
        expect(eval('2.0 < 1.0'), 'false');
      });
      test('<=', () {
        expect(eval('1 <= 1.0'), 'true');
        expect(eval('2.0 <= 1.0'), 'false');
      });
      test('>', () {
        expect(eval('2 > 1'), 'true');
        expect(eval('1.0 > 2.0'), 'false');
      });
      test('>=', () {
        expect(eval('1 >= 1.0'), 'true');
        expect(eval('1.0 >= 2.0'), 'false');
      });
    });

    test('conditional', () {
      expect(eval('true ? 1 : 2'), '1');
      expect(eval('false ? 1 : 2'), '2');
    });

    test('variable ref', () {
      expect(eval('main'), "Instance of 'DartiFunction'");
    });

    group('logical', () {
      test('!', () {
        expect(eval('!true'), 'false');
        expect(eval('!false'), 'true');
      });
      test('&&', () {
        expect(eval('false && false'), 'false');
        expect(eval('true && false'), 'false');
        expect(eval('true && true'), 'true');
      });
      test('||', () {
        expect(eval('false || false'), 'false');
        expect(eval('true || false'), 'true');
        expect(eval('true || true'), 'true');
      });
    });
  });

  group('statements', () {
    test('function declaration', () {
      expect(run('inc(n) => n + 1; main() { print(inc(3)); }'), '4\n');
      expect(run('inc(n) { return n + 1; } main() { print(inc(3)); }'), '4\n');
    });
    test('variable declaration', () {
      expect(run('main() { var a = 42; print(a); }'), '42\n');
      expect(run('main() { final a = 42; print(a); }'), '42\n');
      expect(run('main() { int a = 42; print(a); }'), '42\n');
      expect(run('main() { const a = 42; print(a); }'), '42\n');
    });
    group('assignment', () {
      test('=', () {
        expect(run('main() { var a = 1; a = a + 2; print(a); }'), '3\n');
      });
      test('compound', () {
        expect(run('main() { var a = 1; a += 2; print(a); }'), '3\n');
        expect(run('main() { var a = 1; a -= 2; print(a); }'), '-1\n');
        expect(run('main() { var a = 2; a *= 2; print(a); }'), '4\n');
        expect(run('main() { var a = 3; a /= 2; print(a); }'), '1.5\n');
        expect(run('main() { var a = 3; a ~/= 2; print(a); }'), '1\n');
        expect(run('main() { var a = 3; a %= 2; print(a); }'), '1\n');
      });
    });
    group('prefix', () {
      test('++', () {
        expect(run('main() { var a = 1; print(++a); print(a); }'), '2\n2\n');
      });
      test('--', () {
        expect(run('main() { var a = 1; print(--a); print(a); }'), '0\n0\n');
      });
    });
    group('postfix', () {
      test('++', () {
        expect(run('main() { var a = 1; print(a++); print(a); }'), '1\n2\n');
      });
      test('--', () {
        expect(run('main() { var a = 1; print(a--); print(a); }'), '1\n0\n');
      });
    });
    test('if', () {
      expect(run('main() { if (true) print("T"); }'), 'T\n');
      expect(run('main() { if (false) print("T"); }'), '');
      expect(run('main() { if (false) print("T"); else print("F"); }'), 'F\n');
      expect(run('main() { if (false) { print("T"); } else { print("F"); } }'), 'F\n');
      expect(run('main() { if (false) { print("T"); } else if (true) { print("E"); } }'), 'E\n');
    });
    test('while', () {
      expect(run('main() { while(false) { } }'), '');
      expect(run('main() { var i = 0; while(i < 3) { print(i++); } }'), '0\n1\n2\n');
      expect(run('main() { var i = 0; while(i < 3) { if (i == 2) break; print(i++); } }'), '0\n1\n');
      expect(run('main() { var i = 0; while(i++ < 3) { if (i == 1) continue; print(i); } }'), '2\n3\n');
    });
    test('do/while', () {
      expect(run('main() { do { print("A"); } while(false); }'), 'A\n');
      expect(run('main() { var i = 0; do { print(i); } while(i++ < 2); }'), '0\n1\n2\n');
      expect(run('main() { var i = 0; do { if (i == 1) break; print(i); } while(i++ < 2); }'), '0\n');
      expect(run('main() { var i = 0; do { if (i == 1) continue; print(i); } while(i++ < 2); }'), '0\n2\n');
    });
    test('for/next', () {
      expect(run('main() { for (var i = 0; i < 3; i++) print(i); }'), '0\n1\n2\n');
      expect(run('main() { for (var i = 0; i < 3; i++) { if(i == 2) break; print(i); } }'), '0\n1\n');
      expect(run('main() { for (var i = 0; i < 3; i++) { if(i == 1) continue; print(i); } }'), '0\n2\n');
    });
    test('for/each', () {
      expect(run('main() { for (final a in []) print(a); }'), '');
      expect(run('main() { for (final a in [3, 4, 2]) print(a); }'), '3\n4\n2\n');
      expect(run('main() { for (final a in [3, 4, 2]) { if (a == 2) break; print(a); } }'), '3\n4\n');
      expect(run('main() { for (final a in [3, 4, 2]) { if (a == 4) continue; print(a); } }'), '3\n2\n');
    });
    test('try/catch', () {
      expect(run('main() { try { print("B"); 1~/0; print("E"); } catch (e) { print("C"); } }'), 'B\nC\n');
      expect(run('main() { try { print("B"); 1~/1; print("E"); } catch (e) { print("C"); } }'), 'B\nE\n');
      expect(run('main() { for (var i in [1, 2]) { try { break; } catch (e, st) { print("X"); } } }'), '');
    });
  });

  group('exceptions', () {
    test('unbound variable reference', () {
      expect(() => eval('foo'), throwsDartiException);
    });
    test('assignment to unbound variable', () {
      expect(() => eval('foo = 1'), throwsDartiException);
    });
    test('print with wrong number of arguments', () {
      expect(() => eval('print()'), throwsDartiException);
      expect(() => eval('print(1, 2)'), throwsDartiException);
    });
  });

  group('examples', () {
    test('factorial', () {
      expect(run('''
        fac(n) {
          if (n == 0) return 1;
          return fac(n - 1) * n;
        }
        main() {
          print(fac(0));
          print(fac(1));
          print(fac(10));
        }'''), '1\n1\n3628800\n');
    });
    test('string methods', () {
      expect(run('main() { print("".isEmpty); }'), 'true\n');
      expect(run('main() { print("abc".length); }'), '3\n');
      expect(run('main() { print("abc".substring(1)); }'), 'bc\n');
    });
    test('parse numbers', () {
      expect(run('main() { print(int.parse("13")); }'), '13\n');
      expect(run('main() { print(double.parse("13")); }'), '13.0\n');
    });
  });

  test('function', () {
    expect(eval('(){}'), "Instance of 'DartiFunction'");
    expect(eval('(a){ return a + 1; }(2)'), '3');
    expect(eval('((a) => a - 1)(2)'), '1');
  });
}
