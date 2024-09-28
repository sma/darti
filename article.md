# Creating a Dart Interpreter

Here's an example how to use the `analyzer` package to create an interpreter for a tiny subset of Dart, inspired by the [recent Tart posting](https://www.reddit.com/r/FlutterDev/comments/1fqpizo/looking_for_advice_on_my_sideproject/).

You can use the `analyzer` parse Dart source code and generate an AST and then "just" write an interpreter for that AST. Note that by default, the AST isn't type-checked. I also don't deal with any kind of error handling.

Start like so:

```dart
    void main(List<String> arguments) {
      final result = parseString(
        content: 'void main() { print(3+4); }',
      );
      execute(result.unit);
    }
```

An empty `execute` function boilerplate looks like this:

```dart
    void execute(AstNode node) {
      switch (node) {
        case CompilationUnit():
          executeAll(node.declarations);
        default:
          throw UnimplementedError('${node.runtimeType}: $node');
      }
    }

    void executeAll(NodeList<AstNode> nodes) {
      for (final node in nodes) {
        execute(node);
      }
    }
```

Running this, you'll get an `UnimplementedError: FuncionDeclarationImpl` and have to think about a way to declare (global) functions and call them thereafter. Here's the most simplest way that could possible work:

```dart
    final bindings = <String, Object?>{};

    class DartFunction {
      DartFunction(this.function);

      DartFunction.from(FunctionExpression expr)
          : function = ((arguments) {
              throw UnimplementedError('later');
            });

      final Object? Function(List<Object?> arguments) function;

      Object? call(List<Object?> arguments) => function(arguments);
    }
```

I introduce `DartFunction` to provide a bit of type-safety and also to not confuse a runtime Dart function created the the interpreter with a function of the interpreter runtime because both could be bound.

```dart
    ...
    case FunctionDeclaration():
      bindings[node.name.lexeme] = DartFunction.from(node.functionExpression);
    ...
```

Next, we must implement a way to call functions and execute their body (ignoring parameters and arguments for now, but already implementing `return` statement because I couldn't remember my initial example and thought, I used that statement; it's the classical way to (mis)use custom exceptions):

```dart
      DartFunction.from(FunctionExpression expr)
          : function = ((arguments) {
              try {
                execute(expr.body);
              } on DartReturn catch (r) {
                return r.value;
              }
            });

    class DartReturn implements Exception {
      DartReturn(this.value);

      final Object? value;
    }
```

Add a this to the end of `main`:

```dart
    ...
    if (bindings['main'] case DartFunction main) {
      main(arguments);
    } else {
      throw "missing 'main' function";
    }
```

Running this, you'll get an `UnimplementedError: BlockFunctionBodyImpl`, so we have to create another `AstNode` case. Such a `BlockFunctionBody` contains a `Body` and that has a list of statements we need to `execute`:

```dart
    ...
    case BlockFunctionBody():
      execute(node.block);
    case Block():
      executeAll(node.statements);
    ...
```

The `print(3+4);` is an `ExpressionStatement` which means that we have to switch from executing statements to evaluating expressions, using an `evaluate` function which is yet another big `switch`.

```dart
    Object? evaluate(Expression expr) {
      switch (expr) {
        case MethodInvocation():
          final function = evaluate(expr.function);
          final arguments = [...expr.argumentList.arguments.map(evaluate)];
          if (function is! DartFunction) throw TypeError();
          return function(arguments);
        default:
          throw UnimplementedError('${expr.runtimeType}: $expr');
      }
    }
```

The `function` is a `SimpleIdentifier` and we should introduce a context of frames to represent the current context to correctly map Dart's runtime semantics, but for now, I'm just using my global bindings map, adding a builtin `print` function:

```dart
    final bindings = <String, Object?>{
      'print': DartFunction((args) {
        if (args.length != 1) throw TypeError();
        return print(args.single);
      })
    };

    Object? lookup(String name) {
      return bindings[name] ?? (throw 'unbound identifier $name');
    }
```

Then add this to `evaluate`:

```dart
    ...
    case SimpleIdentifier():
      return lookup(expr.name);
    ...
```

The remaining missing nodes are `BinaryExpression` and `IntegerLiteral`:

```dart
    ...
    case BinaryExpression():
      final left = evaluate(expr.leftOperand);
      final right = evaluate(expr.rightOperand);
      switch (expr.operator.lexeme) {
        case '+':
          if (left is num && right is num) return left + right;
          if (left is String && right is String) return left + right;
          throw TypeError();
        default:
          throw UnimplementedError('$expr');
      }
    case IntegerLiteral():
      return expr.value!;
    ...
```

Running this application should print "7".

For a more complex example, let's change the example to

```dart
    main() { print(sum(3, 4)); } sum(a, b) { return a + b; }
```

We're missing the `ReturnStatement` now. You should be able to implement this yourself because everything we need is already in place. Add this to `execute`:

```dart
    ...
    case ReturnStatement():
      throw DartReturn(node.expression?.let(evaluate));
    ...
```

I'm using a neat trick to deal with the often occuring pattern "if foo != null then bar(foo!) else ..." in a more functional way by using this extension method:

```dart
    extension LetExtension<T> on T {
      U let<U>(U Function(T) transform) => transform(this);
    }
```

We need to bind arguments to parameters when calling a function, and for now, I'll use the global bindings map even if this is wrong:

```dart
    class DartFunction {
      ...

      DartFunction.from(FunctionExpression expr, DartContext context)
          : function = ((arguments) {
              // assuming everything are required positional parameters
              final parameters = [...?expr.parameters?.parameters.map((p) => p.name!.lexeme)];
              // sanity check, assuming all types are matching
              if (parameters.length != arguments.length) throw TypeError();
              for (final (index, parameter) in parameters.indexed) {
                bindings[parameter] = arguments[index];
              }
              ...
    }
```

And our application should print "7" if run again.

Using `sum(a, b) => a + b;` whould be more idiomatic Dart, though. This is an `ExpressionFunctionBody` and we have to add yet another case to `execute`:

```dart
    ...
    case ExpressionFunctionBody():
      throw DartReturn(evaluate(node.expression));
```

I cannot end this article without implementing the _factional_ function:

```dart
    fac(n) => n == 0 ? 1 : fac(n - 1) * n; main() { print(fac(0)); }
```

Running the application shows, that we're lacking a `ConditionalExpression` in `evaluate`:

```dart
    ...
    case ConditionalExpression():
      return evaluate(evaluate(expr.condition) as bool 
        ? expr.thenExpression : expr.elseExpression);
    ...
```

And of course the implementations for `==`, `-` and `*`, which I can add to the `switch` that currently implements addition only:

```dart
        ...
        case '-':
          if (left is num && right is num) return left - right;
          throw TypeError();
        case '*':
          if (left is num && right is num) return left * right;
          if (left is String && right is int) return left * right;
          throw TypeError();
        case '==':
          return left == right;
        ...
```

The application now prints "1". But this was the non-recursive case and something like `fac(5)` (which should print "120") doesn't work because I don't correctly bind new parameters and everything gets overwritten in the global environment. So, let's fix that by refactoring the whole application and creating a `DartContext` class which has a `bindings` property as well as the already existing `execute` and `evaluate` methods.

```dart
    class DartContext {
      DartContext(this.parent, this.bindings);
    
      final DartContext? parent;
      final Map<String, Object?> bindings;
    
      Object? lookup(String name) {
        if (bindings.containsKey(name)) return bindings[name];
        return (parent ?? (throw 'unbound identifier $name')).lookup(name);
      }
    
      static final global = DartContext(null, {
        'print': DartFunction((args) {
          if (args.length != 1) throw TypeError();
          return print(args.single);
        }),
      });
    
      void execute(AstNode node) {
        ...
      }

      void executeAll(NodeList<AstNode> nodes) {
        ...
      }

      Object? evaluate(Expression expr) {
        ...
      }
    }
```

I must now use `DartContext.global` in `main`:

```dart
    void main(List<String> arguments) {
      final result = parseString(
          content: 'fac(n) => n == 0 ? 1 : fac(n - 1) * n; main() { print(fac(5)); }',
      );
      DartContext.global.execute(result.unit);
    
      if (DartContext.global.bindings['main'] case DartFunction main) {
        main(arguments);
      } else {
        throw "missing 'main' function";
      }
    }
```

Next, we need to pass the current context to `DartFunction.from` so that a call to a function can create a new context based on the definiting context to bind arguments to parameters. Note how I use a `for` inside the `{}` to define the new bindings and then use the new context to evaluate the function body.

```dart
    class DartFunction {
      ...

      DartFunction.from(FunctionExpression expr, DartContext context)
          : function = ((arguments) {
              // assuming everything are required positional parameters
              final parameters = [...?expr.parameters?.parameters.map((p) => p.name!.lexeme)];
              // sanity check, assuming all types are matching
              if (parameters.length != arguments.length) throw TypeError();
              try {
                DartContext(context, {
                  for (final (index, parameter) in parameters.indexed) //
                    parameter: arguments[index],
                }).execute(expr.body);
                return null; // void function
              } on DartReturn catch (r) {
                return r.value;
              }
            });

      ...
    }
```

And voila, the interpreter correctly prints "120", so recursive function call (and other function calls, too), work as expected. This starts to become actually useful.

Of course, is it just the tip of the iceberg, as we only support functions and simple expressions. Adding conditionals and loops shouldn't be difficult. A switch with pattern matching on the other hand, would be difficult. You'd also have to think about how to pass `DartFunction` objects to built-in functions because Dart has no easy way to deal with different arities, like for example an `apply` function. And classes, methods and method calls are in a whole different league. Because we cannot create real Dart classes or methods at runtime, we need to simulate them and then distinguish between classes of the runtime environment and user defined classes. And if we want to use this interpreter with Flutter or other AOT compiled environment, we cannot use mirrors to directly call built-in stuff, but need to create our own shadow class hierarchy, similar to how I mapped the `print` function.

That get's very tedious fast and I'd recommend to write some code that automatically generates this for the standard library, using mirrors. It was always the point in time where I gave up.

Just try this:

```dart
    main() { print("abc".substring(1)); }
```

This complains about a missing `substring` identifier which means, that I failed to correctly implement `MethodInvocation` because the code doesn't know that `substring` is a method of `String` instead of a global function. It seems, we have take `realTarget` into account.

```dart
      ...
      case MethodInvocation():
        if (expr.realTarget case final realTargetExpr?) {
          final target = evaluate(realTargetExpr);
          if (expr.function case SimpleIdentifier name) {
            final arguments = [...expr.argumentList.arguments.map(evaluate)];
            return reflect(target).invoke(Symbol(name.name), arguments).reflectee;
          }
          throw TypeError();
        }
        ...
```

Hopefully, the method name is always a `SimpleIdentifier`. Then, I'll try to call that method with the evaluates arguments using the `mirrors` package. Very convenient. Without that package, you'd have to recreate the whole class hierarchy, as Dart has no way to determine a supertype of a runtime type which would be needed to traverse a type hierarchy to find the correct method implementation.
