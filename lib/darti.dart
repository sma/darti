import 'dart:mirrors';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:darti/let.dart';
import 'package:pub_semver/pub_semver.dart';

class DartiFunction {
  DartiFunction(this.function);

  DartiFunction.from(FunctionExpression expr, Darti context)
      : function = ((arguments) {
          // assuming everything are required positional parameters
          final parameters = [...?expr.parameters?.parameters.map((p) => p.name!.lexeme)];
          // sanity check, assuming all types are matching
          if (parameters.length != arguments.length) throw TypeError();
          try {
            Darti(context, {
              for (final (index, parameter) in parameters.indexed) //
                parameter: arguments[index],
            }).execute(expr.body);
            return null; // void function
          } on _Return catch (r) {
            return r.value;
          }
        });

  final Object? Function(List<Object?> arguments) function;

  Object? call(List<Object?> arguments) => function(arguments);
}

// class DartiException implements Exception {
//   DartiException(this.message);

//   final String message;

//   @override
//   String toString() => message;
// }

/// Interprets Dart code.
///
/// Use [Darti.global] for a context that has a predefined `print` function.
///
/// Use [Darti.main] to run some Dart source code that contains a `main`
/// function. You can optionally pass a list of string arguments.
class Darti {
  Darti(this.parent, this.bindings);

  final Darti? parent;
  final Map<String, Object?> bindings;

  Object? lookup(String name) {
    if (bindings.containsKey(name)) {
      return bindings[name];
    }
    return (parent ?? (throw 'unbound identifier $name')).lookup(name);
  }

  T update<T>(String name, T value) {
    if (bindings.containsKey(name)) {
      return bindings[name] = value;
    }
    return (parent ?? (throw 'unbound identifier $name')).update(name, value);
  }

  static final global = Darti(null, {
    'print': DartiFunction((args) {
      if (args.length != 1) throw TypeError();
      return print(args.single);
    }),
  });

  void execute(AstNode node) {
    switch (node) {
      case CompilationUnit():
        executeAll(node.declarations);
      case FunctionDeclaration():
        bindings[node.name.lexeme] = DartiFunction.from(node.functionExpression, this);
      case BlockFunctionBody():
        execute(node.block);
      case ExpressionFunctionBody():
        throw _Return(evaluate(node.expression));
      case Block():
        executeAll(node.statements);
      case ExpressionStatement():
        evaluate(node.expression);
      case ReturnStatement():
        throw _Return(node.expression?.let(evaluate));
      case VariableDeclarationStatement():
        // ignores final/const/etc.
        executeAll(node.variables.variables);
      case VariableDeclaration():
        bindings[node.name.lexeme] = node.initializer?.let(evaluate);
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
        // XXX this should be in child context
        executeAll(node.variables.variables);
        while (node.condition?.let(evaluateAsBool) ?? true) {
          try {
            execute((node.parent as ForStatement).body);
          } on _Break {
            break;
          } on _Continue {
            // continue below
          }
          for (final updater in node.updaters) {
            evaluate(updater);
          }
        }
      case ForEachPartsWithDeclaration():
        // XXX this should be in child context
        final name = node.loopVariable.name.lexeme;
        final iterable = evaluate(node.iterable);
        if (iterable is! Iterable) throw TypeError();
        for (final value in iterable) {
          bindings[name] = value;
          try {
            execute((node.parent as ForStatement).body);
          } on _Break {
            break;
          } on _Continue {
            continue;
          }
        }
      case BreakStatement():
        throw _Break();
      case ContinueStatement():
        throw _Continue();
      default:
        throw UnimplementedError('${node.runtimeType}: $node'); // coverage:ignore-line
    }
  }

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
            final arguments = [...node.argumentList.arguments.map(evaluate)];
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
            return reflect(target).invoke(Symbol(name.name), arguments).reflectee;
          }
          throw TypeError(); // coverage:ignore-line
        }
        final function = evaluate(node.function);
        final arguments = [...node.argumentList.arguments.map(evaluate)];
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
        final left = evaluate(node.leftOperand);
        final right = evaluate(node.rightOperand);
        switch (node.operator.lexeme) {
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
      case PrefixExpression():
        switch (node.operator.lexeme) {
          case '-':
            return -(evaluate(node.operand) as num);
          default:
            throw UnimplementedError('$node'); // coverage:ignore-line
        }
      case PostfixExpression():
        final value = evaluate(node.operand);
        if (node.operand case SimpleIdentifier operand) {
          switch (node.operator.lexeme) {
            case '++':
              update(operand.name, (value as num) + 1);
            case '--':
              update(operand.name, (value as num) - 1);
            default:
              throw UnimplementedError('$node'); // coverage:ignore-line
          }
        } else {
          throw UnimplementedError('$node is not a simple identifier'); // coverage:ignore-line
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
          _evaluateCollectionElement(list, element);
        }
        return list;
      case SetOrMapLiteral():
        final list = <dynamic>[];
        for (final element in node.elements) {
          _evaluateCollectionElement(list, element);
        }
        if (list.isEmpty) return {};
        if (list.first is MapEntry<dynamic, dynamic>) {
          return Map.fromEntries(list.cast<MapEntry<dynamic, dynamic>>());
        }
        return list.toSet();
      case AssignmentExpression():
        // XXX needs to deal with complex LHS
        final name = node.leftHandSide as SimpleIdentifier;
        var value = evaluate(node.rightHandSide);
        switch (node.operator.lexeme) {
          case '=':
            break;
          case '+=':
            value = (bindings[name.name] as num) + (value as num);
          case '-=':
            value = (bindings[name.name] as num) - (value as num);
          default:
            throw UnimplementedError('$node'); // coverage:ignore-line
        }
        return update(name.name, value);
      default:
        throw UnimplementedError('${node.runtimeType}: $node'); // coverage:ignore-line
    }
  }

  /// Returns the result of evaluating [node] which must be a Boolean value.
  bool evaluateAsBool(Expression node) => evaluate(node) as bool;

  void _evaluateCollectionElement(List<dynamic> list, CollectionElement element) {
    switch (element) {
      case Expression():
        list.add(evaluate(element));
      case ForElement():
        throw UnimplementedError();
      case IfElement():
        if (evaluateAsBool(element.expression)) {
          _evaluateCollectionElement(list, element.thenElement);
        } else if (element.elseElement case final elseElement?) {
          _evaluateCollectionElement(list, elseElement);
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

class _Break implements Exception {}

class _Continue implements Exception {}

class _Return implements Exception {
  _Return(this.value);

  final Object? value;
}
