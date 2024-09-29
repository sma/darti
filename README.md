An Interpreter For a Tiny Subset of Dart
========================================

Run simple Dart code like

```dart
fac(n) => n == 0 ? 1 : fac(n - 1) * n;

main() { print(fac(10)); }
```

by passing a string to `DartContext.main()`.

This is an extended version from [an article](article.md) that I wrote on a whim.

The interpreter currently knows about basic arithmetic and comparsion operations as well as some basic control structure and simple function and variable declarations. It completely ignores types. It also ignores most other modern Dart features. It cannot deal with classes or methods.

To access methods and properties of built-in types, `mirrors` are used which makes it impossible to use this interpreter in AOT compiling environments like Flutter. I intent to change this, though.

Run `dart run` to execute `bin/darti.dart` which demonstrates the factorial function.

Run `dart test` to run all tests. Alternatively, you can run `make` to run all tests with code coverage. I recommend the [coverage-gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) extension for Visual Studio Code to show which lines are covered by tests and aren't yet.

Run `dart run :hammudarti` for a non trivial example of a [old game](https://archive.org/details/Basic_Computer_Games_Microcomputer_Edition_1978_Creative_Computing/page/n92/mode/1up) running via Darti. Note that I simply asked Claude.ai for some code that resembles that game. The implementation is actually wrong.

## Subset Supported
Below is a list of all concrete `AstNode`s of Dart 3.5 with the exception of augmentation that are created by the Dart parser.

### Statements
* [ ] `AssertStatement`
* [X] `Block` - creates a new context
* [X] `BreakStatement` - no label
* [X] `ContinueStatement` - no label
* [X] `DoStatement`
* [X] `EmptyStatement`
* [X] `ExpressionStatement`
* [X] `ForStatement`
* [X] `FunctionDeclarationStatement`
* [X] `IfStatement`
* [ ] `LabeledStatement`
* [ ] `PatternVariableDeclarationStatement`
* [X] `ReturnStatement`
* [ ] `SwitchStatement`
* [X] `TryStatement` - no type matching
* [X] `VariableDeclarationStatement` - everything is mutable
* [X] `WhileStatement`
* [ ] `YieldStatement`

### Expressions
* [ ] `AsExpression` - missing
* [ ] `AwaitExpression` - missing
* [X] `BinaryExpression` - no binary operations
* [ ] `CascadeExpression` - missing
* [X] `ConditionalExpression`
* [X] `FunctionExpression` - no named parameters
* [X] `FunctionExpressionInvocation` - no named parameters
* [ ] `FunctionReference` - resolver?
* [ ] `InstanceCreationExpression` - missing
* [ ] `IsExpression` - missing
* [ ] `MethodInvocation` - missing
* [ ] `NamedExpression` - missing
* [X] `ParenthesizedExpression`
* [ ] `PatternAssignment` - missing
* [X] `PostfixExpression`
* [ ] `PrefixedIdentifier` - missing
* [X] `PrefixExpression` - no binary `~`
* [ ] `RethrowExpression` - missing
* [X] `SimpleIdentifier`
* [ ] `SuperExpression` - missing
* [ ] `SwitchExpression` - missing
* [ ] `ThisExpression` - missing
* [ ] `ThrowExpression` - missing

### Literals
* [X] `BooleanLiteral`
* [X] `DoubleLiteral`
* [X] `IntegerLiteral`
* [X] `ListLiteral` - no support for `<type>[...]`
* [X] `NullLiteral`
* [ ] `RecordLiteral` - missing
* [X] `SetOrMapLiteral` - no support for `<type>{...}`
* [X] `StringLiteral`
* [ ] `SymbolLiteral` - missing
