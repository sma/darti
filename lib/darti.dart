import 'dart:mirrors';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:darti/let.dart';
import 'package:pub_semver/pub_semver.dart';

/// Represents a built-in or user-defined function.
class DartiFunction {
  DartiFunction(this.function);

  DartiFunction.from(FunctionExpression expr, Darti context)
      : function = ((arguments) {
          // assuming all parameters are required and positional
          final parameterExprs = expr.parameters?.parameters;
          if (parameterExprs?.any((p) => p.isNamed || p.isOptional) ?? false) throw TypeError();
          final parameters = [...?parameterExprs?.map((p) => p.name!.lexeme)];
          // sanity check, assuming all types are matching
          if (parameters.length != arguments.length) throw TypeError();
          try {
            Darti(context, {
              for (final (index, parameter) in parameters.indexed) parameter: arguments[index],
            }).execute(expr.body);
            return null; // void function
          } on _Return catch (r) {
            return r.value;
          }
        });

  final Object? Function(List<Object?> arguments) function;

  Object? call(List<Object?> arguments) => function(arguments);
}

class DartiException implements Exception {
  DartiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Interprets Dart code.
///
/// Use [Darti.global] for a context that has a predefined `print` function.
///
/// Use [Darti.main] to run some Dart source code that contains a `main`
/// function. You can optionally pass a list of string arguments.
class Darti {
  Darti(this.parent, this.bindings);

  /// The parent context, used to [lookup] bindings.
  final Darti? parent;

  /// The values bound to names in this context.
  final Map<String, Object?> bindings;

  /// Returns the value bound to [name].
  /// Throws an error if unbound.
  Object? lookup(String name) {
    if (bindings.containsKey(name)) {
      return bindings[name];
    }
    return (parent ?? (throw DartiException('unbound identifier $name'))).lookup(name);
  }

  /// Updates the binding of [name] to [value] and returns it.
  /// To create a new binding, directly assign to [bindings] instead.
  /// Throws an error if unbound.
  T update<T>(String name, T value) {
    if (bindings.containsKey(name)) {
      return bindings[name] = value;
    }
    return (parent ?? (throw DartiException('unbound identifier $name'))).update(name, value);
  }

  static void checkArguments(int count, List<Object?> args) {
    if (args.length != count) {
      throw DartiException('expected ${count == 1 ? '1 argument' : '$count arguments'} but got ${args.length}');
    }
  }

  static final global = Darti(null, {
    'int': int,
    'double': double,
    'print': DartiFunction((args) {
      checkArguments(1, args);
      return print(args.single);
    }),
  });

  /// Executes [node].
  void execute(AstNode node) {
    switch (node) {
      case CompilationUnit():
        executeAll(node.declarations);
      case EmptyFunctionBody():
        break;
      case FunctionDeclaration():
        bindings[node.name.lexeme] = DartiFunction.from(node.functionExpression, this);
      case BlockFunctionBody():
        execute(node.block);
      case ExpressionFunctionBody():
        throw _Return(evaluate(node.expression));
      case Block():
        Darti(this, {}).executeAll(node.statements);
      case ExpressionStatement():
        evaluate(node.expression);
      case ReturnStatement():
        throw _Return(node.expression?.let(evaluate));
      case VariableDeclarationStatement():
        // ignores final/const/etc.
        executeAll(node.variables.variables);
      case VariableDeclaration():
        bindings[node.name.lexeme] = node.initializer?.let(evaluate);
      case TopLevelVariableDeclaration():
        executeAll(node.variables.variables);
      case IfStatement():
        if (evaluateAsBool(node.expression)) {
          execute(node.thenStatement);
        } else if (node.elseStatement case final elseStatement?) {
          execute(elseStatement);
        }
      case WhileStatement():
        while (evaluateAsBool(node.condition)) {
          try {
            execute(node.body);
          } on _Break {
            break;
          } on _Continue {
            continue;
          }
        }
      case DoStatement():
        do {
          try {
            execute(node.body);
          } on _Break {
            break;
          } on _Continue {
            continue;
          }
        } while (evaluateAsBool(node.condition));
      case ForStatement():
        execute(node.forLoopParts);
      case ForPartsWithDeclarations():
        Darti(this, {})._executeForParts(node);
      case ForPartsWithExpression():
        Darti(this, {})._executeForParts(node);
      case ForEachPartsWithDeclaration():
        final name = node.loopVariable.name.lexeme;
        final body = (node.parent as ForStatement).body;
        final iterable = evaluate(node.iterable);
        if (iterable is! Iterable) throw TypeError();
        for (final value in iterable) {
          try {
            Darti(this, {name: value}).execute(body);
          } on _Break {
            break;
          } on _Continue {
            continue;
          }
        }
      case ForEachPartsWithIdentifier():
        final body = (node.parent as ForStatement).body;
        final iterable = evaluate(node.iterable);
        if (iterable is! Iterable) throw TypeError();
        for (final value in iterable) {
          try {
            assign(node.identifier, value);
            execute(body);
          } on _Break {
            break;
          } on _Continue {
            continue;
          }
        }
      case BreakStatement():
        throw const _Break();
      case ContinueStatement():
        throw const _Continue();
      case TryStatement():
        try {
          execute(node.body);
        } on _ControlFlow {
          rethrow;
        } catch (exception) {
          for (final catchClause in node.catchClauses) {
            if (catchClause.exceptionType != null) throw UnsupportedError('on ${catchClause.exceptionType}');
            var context = this;
            if (catchClause.exceptionParameter?.name.lexeme case final name?) {
              context = Darti(context, {name: exception});
            }
            context.execute(catchClause.body);
          }
        } finally {
          node.finallyBlock?.let(execute);
        }
      case EmptyStatement():
        break;
      case FunctionDeclarationStatement():
        execute(node.functionDeclaration);
      default:
        throw UnimplementedError('${node.runtimeType}: $node'); // coverage:ignore-line
    }
  }

  /// This is called by [execute] on a new context so that the variables
  /// declared by executing this [node] are local to the `for` loop.
  void _executeForParts(ForParts node) {
    switch (node) {
      case ForPartsWithDeclarations():
        executeAll(node.variables.variables);
      case ForPartsWithExpression():
        node.initialization?.let(evaluate);
      case ForPartsWithPattern():
        throw UnimplementedError('$node');
    }
    final body = (node.parent as ForStatement).body;
    while (node.condition?.let(evaluateAsBool) ?? true) {
      try {
        execute(body);
      } on _Break {
        break;
      } on _Continue {
        // continue below
      }
      for (final updater in node.updaters) {
        evaluate(updater);
      }
    }
  }

  /// Executes every node in [nodes].
  void executeAll(NodeList<AstNode> nodes) {
    for (final node in nodes) {
      execute(node);
    }
  }

  /// Returns the result of evaluating [node].
  Object? evaluate(Expression node) {
    switch (node) {
      case MethodInvocation():
        if (node.realTarget case final targetExpr?) {
          final target = evaluate(targetExpr);
          if (node.function case SimpleIdentifier name) {
            final arguments = evaluateArgumentList(node.argumentList);
            // if (target is String) {
            //   switch (name.name) {
            //     case 'substring':
            //       if (arguments.length == 1) return target.substring(arguments[0] as int);
            //       if (arguments.length == 2) return target.substring(arguments[0] as int, arguments[1] as int);
            //       throw TypeError();
            //     default:
            //       throw UnsupportedError('String has no method mapping for $name');
            //   }
            // }
            // if (target == int && name.name == 'parse') {
            //   return int.parse(arguments.single as String);
            // }
            if (target is Type) {
              return reflectClass(target).invoke(Symbol(name.name), arguments).reflectee;
            }
            return reflect(target).invoke(Symbol(name.name), arguments).reflectee;
          }
          throw TypeError(); // coverage:ignore-line
        }
        final function = evaluate(node.function);
        final arguments = evaluateArgumentList(node.argumentList);
        if (function is DartiFunction) return function(arguments);
        throw TypeError(); // coverage:ignore-line
      case PropertyAccess():
        final target = evaluate(node.realTarget);
        final name = node.propertyName.name;
        // if (target is String) {
        //   switch (name) {
        //     case 'isEmpty':
        //       return target.isEmpty;
        //     case 'length':
        //       return target.length;
        //     default:
        //       throw UnsupportedError('String has no property mapping for $name');
        //   }
        // }
        return reflect(target).getField(Symbol(name)).reflectee;
      case SimpleIdentifier():
        return lookup(node.name);
      case BinaryExpression():
        final operator = node.operator.lexeme;
        final left = evaluate(node.leftOperand);
        switch (operator) {
          case '&&':
            return left as bool && evaluate(node.rightOperand) as bool;
          case '||':
            return left as bool || evaluate(node.rightOperand) as bool;
          default:
            final right = evaluate(node.rightOperand);
            switch (operator) {
              case '+':
                if (left is num && right is num) return left + right;
                if (left is String && right is String) return left + right;
                throw TypeError(); // coverage:ignore-line
              case '-':
                if (left is num && right is num) return left - right;
                throw TypeError(); // coverage:ignore-line
              case '*':
                if (left is num && right is num) return left * right;
                if (left is String && right is int) return left * right;
                throw TypeError(); // coverage:ignore-line
              case '/':
                if (left is num && right is num) return left / right;
                throw TypeError(); // coverage:ignore-line
              case '~/':
                if (left is num && right is num) return left ~/ right;
                throw TypeError(); // coverage:ignore-line
              case '%':
                if (left is num && right is num) return left % right;
                throw TypeError(); // coverage:ignore-line
              case '==':
                return left == right;
              case '!=':
                return left != right;
              case '<':
                return left as dynamic < right;
              case '<=':
                return left as dynamic <= right;
              case '>':
                return left as dynamic > right;
              case '>=':
                return left as dynamic >= right;
              default:
                throw UnimplementedError('$node'); // coverage:ignore-line
            }
        }

      case PrefixExpression():
        final value = evaluate(node.operand);
        switch (node.operator.lexeme) {
          case '-':
            return -(value as num);
          case '++':
            return assign(node.operand, (value as num) + 1);
          case '--':
            return assign(node.operand, (value as num) - 1);
          case '!':
            return !(value as bool);
          default:
            throw UnimplementedError('$node'); // coverage:ignore-line
        }
      case PostfixExpression():
        final value = evaluate(node.operand) as num;
        switch (node.operator.lexeme) {
          case '++':
            assign(node.operand, value + 1);
          case '--':
            assign(node.operand, value - 1);
          default:
            throw UnimplementedError('$node'); // coverage:ignore-line
        }
        return value;
      case NullLiteral():
        return null;
      case BooleanLiteral():
        return node.value;
      case IntegerLiteral():
        return node.value!;
      case DoubleLiteral():
        return node.value;
      case SimpleStringLiteral():
        return node.value;
      case ConditionalExpression():
        return evaluate(evaluateAsBool(node.condition) ? node.thenExpression : node.elseExpression);
      case StringInterpolation():
        final buf = StringBuffer();
        for (final element in node.elements) {
          switch (element) {
            case InterpolationExpression(:var expression):
              buf.write(evaluate(expression));
            case InterpolationString(:var value):
              buf.write(value);
          }
        }
        return buf.toString();
      case ListLiteral():
        final list = <dynamic>[];
        for (final element in node.elements) {
          _evaluateCollectionElement(element, list);
        }
        return list;
      case SetOrMapLiteral():
        final list = <dynamic>[];
        for (final element in node.elements) {
          _evaluateCollectionElement(element, list);
        }
        if (list.isEmpty) return {};
        if (list.first is MapEntry<dynamic, dynamic>) {
          return Map.fromEntries(list.cast<MapEntry<dynamic, dynamic>>());
        }
        return list.toSet();
      case AssignmentExpression():
        var value = evaluate(node.rightHandSide);
        switch (node.operator.lexeme) {
          case '=':
            break;
          case '+=':
            value = (evaluate(node.leftHandSide) as num) + (value as num);
          case '-=':
            value = (evaluate(node.leftHandSide) as num) - (value as num);
          case '*=':
            value = (evaluate(node.leftHandSide) as num) * (value as num);
          case '/=':
            value = (evaluate(node.leftHandSide) as num) / (value as num);
          case '%=':
            value = (evaluate(node.leftHandSide) as num) % (value as num);
          case '~/=':
            value = (evaluate(node.leftHandSide) as num) ~/ (value as num);
          default:
            throw UnimplementedError('$node'); // coverage:ignore-line
        }
        return assign(node.leftHandSide, value);
      case ParenthesizedExpression():
        return evaluate(node.expression);
      case FunctionExpression():
        return DartiFunction.from(node, this);
      case FunctionExpressionInvocation():
        final function = evaluate(node.function);
        final arguments = evaluateArgumentList(node.argumentList);
        if (function is! DartiFunction) throw TypeError();
        return function(arguments);
      default:
        throw UnimplementedError('${node.runtimeType}: $node'); // coverage:ignore-line
    }
  }

  /// Evaluates all [arguments] into a list of values.
  List<Object?> evaluateArgumentList(ArgumentList arguments) {
    return [...arguments.arguments.map(evaluate)];
  }

  /// Evalutes [element] and append it to [list].
  void _evaluateCollectionElement(CollectionElement element, List<dynamic> list) {
    switch (element) {
      case Expression():
        list.add(evaluate(element));
      case ForElement():
        throw UnimplementedError();
      case IfElement():
        if (evaluateAsBool(element.expression)) {
          _evaluateCollectionElement(element.thenElement, list);
        } else if (element.elseElement case final elseElement?) {
          _evaluateCollectionElement(elseElement, list);
        }
      case MapLiteralEntry():
        list.add(MapEntry<dynamic, dynamic>(evaluate(element.key), evaluate(element.value)));
      case NullAwareElement():
        final value = evaluate(element.value);
        if (value != null) list.add(value);
      case SpreadElement():
        final iterable = evaluate(element.expression);
        if (iterable == null) break;
        if (iterable is! Iterable) {
          if (iterable is! Map<dynamic, dynamic>) throw TypeError();
          list.addAll(iterable.entries);
        } else {
          list.addAll(iterable);
        }
    }
  }

  /// Returns the result of evaluating [node] which must be a Boolean value.
  bool evaluateAsBool(Expression node) => evaluate(node) as bool;

  /// Assigns [value] to [node], returning the assigned value.
  Object? assign(Expression node, Object? value) {
    switch (node) {
      case SimpleIdentifier():
        return update(node.name, value);
      case PrefixedIdentifier():
        final target = evaluate(node.prefix);
        final name = node.identifier.name;
        reflect(target).setField(Symbol(name), value);
        return value;
      default:
        throw UnimplementedError('${node.runtimeType}: $node'); // coverage:ignore-line
    }
  }

  /// Runs [source], throwing an [ArgumentError] on compilation errors.
  /// Might also throw other exceptions or errors because of the execution.
  void run(String source) {
    final result = parseString(
      content: source,
      featureSet: FeatureSet.fromEnableFlags2(
        sdkLanguageVersion: Version(3, 6, 0),
        flags: ['null-aware-elements'],
      ),
    );
    execute(result.unit);
  }

  /// Parses [source] which must contain a `main()` or a `main(arguments)`
  /// function declaration and calls that function with [arguments].
  static void main(String source, [List<String>? arguments]) {
    if ((Darti(Darti.global, {})..run(source)).bindings['main'] case DartiFunction main?) {
      main(arguments ?? const []);
    } else {
      throw ArgumentError("Missing 'main' function");
    }
  }
}

abstract class _ControlFlow implements Exception {}

/// Signals a `break` within a loop.
class _Break implements _ControlFlow {
  const _Break();
}

/// Signals a `continue` within a loop.
class _Continue implements _ControlFlow {
  const _Continue();
}

/// Signals a `return` within a function.
class _Return implements _ControlFlow {
  _Return(this.value);

  final Object? value;
}
