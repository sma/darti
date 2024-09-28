An Interpreter For a Tiny Subset of Dart
========================================

Run simple Dart code like

```dart
fac(n) => n == 0 ? 1 : fac(n - 1) * n;

main() { print(fac(10)); }
```

by passing a string to `DartContext.main()`.

This is an extended version from [an article](article.md) that I wrote on a whim.

The interpreter currently knows about basic arithmetic and comparsion operations as well as some basic control structure and simple function and variable declarations. It completely ignores types. It also ignores most other modern Dart features. It cannot deal with classes or methods. Also, it cannot deal with anonymous functions yet.

To access methods and properties of built-in types, `mirrors` are used which makes it impossible to use this interpreter in AOT compiling environments like Flutter. I intent to change this, though.

Run `dart run` to run `bin/darti.dart` which demonstrates the factorial function.

Run `dart test` to run all tests. Alternatively, you can run `make` to run tests with code coverage. I recommend the [coverage-gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) extension for Visual Studio Code to show which lines are covered by tests and aren't yet.
