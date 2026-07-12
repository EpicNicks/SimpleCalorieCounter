import 'dart:collection';
import 'dart:math' as math;

import '../../../dto/CustomSymbolEntry.dart';
import '../exceptions/AggregateException.dart';
import '../token/InvalidToken.dart';
import '../token/LiteralToken.dart';
import '../token/OperatorToken.dart';
import '../token/Token.dart';
import 'Tokenizer.dart';

({double result, String comment}) parseWithComment(String input) {
  List<Token> tokens = tokenize(input);
  int firstInvalidIndex = tokens.indexWhere((token) => token is InvalidToken);
  String comment = "";
  if (firstInvalidIndex != -1) {
    InvalidToken firstInvalidToken = tokens[firstInvalidIndex] as InvalidToken;
    tokens = tokens.sublist(0, firstInvalidIndex);
    comment = input.substring(firstInvalidToken.position);
  }
  final List<Token> rpnSolveList = _tokensToRpn(tokens);
  final SolveResult solveResult = _shuntingYardSolve(rpnSolveList);
  return (result: solveResult.value, comment: comment);
}

double parse(String input) {
  final List<Token> tokens = tokenize(input);
  final List<Token> rpnSolveList = _tokensToRpn(tokens);
  final SolveResult solveResult = _shuntingYardSolve(rpnSolveList);
  return solveResult.value;
}

double parseWithUserSymbols(String input, List<CustomSymbolEntry> userSymbols) {
  try {
    final List<Token> resolvedTokens = _resolveSymbolsToInput(tokenize(input), userSymbols);
    final List<Token> rpnSolveList = _tokensToRpn(resolvedTokens);
    final SolveResult solveResult = _shuntingYardSolve(rpnSolveList);
    return solveResult.value;
  } catch (e) {
    return 0;
  }
}

({double result, String comment}) parseWithUserSymbolsAndComment(String input, List<CustomSymbolEntry> userSymbols) {
  try {
    List<Token> resolvedTokens = _resolveSymbolsWithCommentsToInput(tokenize(input), userSymbols);
    int firstInvalidIndex = resolvedTokens.indexWhere((token) => token is InvalidToken);
    String comment = "";
    if (firstInvalidIndex != -1) {
      InvalidToken firstInvalidToken = resolvedTokens[firstInvalidIndex] as InvalidToken;
      resolvedTokens = resolvedTokens.sublist(0, firstInvalidIndex);
      comment = input.substring(firstInvalidToken.position);
    }
    final List<Token> rpnSolveList = _tokensToRpn(resolvedTokens);
    final SolveResult solveResult = _shuntingYardSolve(rpnSolveList);
    return (result: solveResult.value, comment: comment);
  } catch (e) {
    return (result: 0, comment: "");
  }
}

({double result, int commentIndex}) parseWithUserSymbolsAndCommentIndex(
    String input, List<CustomSymbolEntry> userSymbols) {
  try {
    List<Token> resolvedTokens = _resolveSymbolsWithCommentsToInput(tokenize(input), userSymbols);
    int firstInvalidIndex = resolvedTokens.indexWhere((token) => token is InvalidToken);
    int commentIndex = -1;
    if (firstInvalidIndex != -1) {
      InvalidToken firstInvalidToken = resolvedTokens[firstInvalidIndex] as InvalidToken;
      resolvedTokens = resolvedTokens.sublist(0, firstInvalidIndex);
      commentIndex = firstInvalidToken.position;
    }
    final List<Token> rpnSolveList = _tokensToRpn(resolvedTokens);
    final SolveResult solveResult = _shuntingYardSolve(rpnSolveList);
    return (result: solveResult.value, commentIndex: commentIndex);
  } catch (e) {
    return (result: 0, commentIndex: -1);
  }
}

List<Token> _resolveSymbolsWithCommentsToInput(List<Token> tokens, List<CustomSymbolEntry> userSymbols) {
  for (int i = 0; i < tokens.length; i++) {
    final Token curToken = tokens[i];
    if (curToken is InvalidToken) {
      try {
        final CustomSymbolEntry? matchedCse =
            userSymbols.where((symbol) => symbol.name == curToken.invalidShard).firstOrNull;
        if (matchedCse == null) {
          // rest is a comment string
          return tokens;
        }
        final List<Token> newTokenData = _resolveSymbolsToInput(tokenize(matchedCse.expression), userSymbols);

        final bool needsLeadingMultiply =
            i > 0 && (tokens[i - 1] is LiteralToken || tokens[i - 1] == OperatorToken.RPAREN);

        final List<Token> expandedTokens = [];
        expandedTokens.addAll(tokens.take(i));
        if (needsLeadingMultiply) {
          expandedTokens.add(OperatorToken.MULTIPLY);
        }
        expandedTokens.add(OperatorToken.LPAREN);
        expandedTokens.addAll(newTokenData);
        expandedTokens.add(OperatorToken.RPAREN);
        expandedTokens.addAll(tokens.skip(i + 1));
        tokens = expandedTokens;
        i--; // Reset index to reprocess from current position
      } catch (e) {
        // Handle missing symbol gracefully or rethrow
        rethrow;
      }
    }
  }
  return tokens;
}

List<Token> _resolveSymbolsToInput(List<Token> tokens, List<CustomSymbolEntry> userSymbols) {
  for (int i = 0; i < tokens.length; i++) {
    final Token curToken = tokens[i];
    if (curToken is InvalidToken) {
      try {
        final CustomSymbolEntry matchedCse = userSymbols.firstWhere((symbol) => symbol.name == curToken.invalidShard,
            orElse: () => throw ArgumentError('Symbol not found: ${curToken.invalidShard}'));
        final List<Token> newTokenData = _resolveSymbolsToInput(tokenize(matchedCse.expression), userSymbols);

        final bool needsLeadingMultiply =
            i > 0 && (tokens[i - 1] is LiteralToken || tokens[i - 1] == OperatorToken.RPAREN);

        final List<Token> expandedTokens = [];
        expandedTokens.addAll(tokens.take(i));
        if (needsLeadingMultiply) {
          expandedTokens.add(OperatorToken.MULTIPLY);
        }
        expandedTokens.add(OperatorToken.LPAREN);
        expandedTokens.addAll(newTokenData);
        expandedTokens.add(OperatorToken.RPAREN);
        expandedTokens.addAll(tokens.skip(i + 1)); // Fixed: was i + 2
        tokens = expandedTokens;
        i--; // Reset index to reprocess from current position
      } catch (e) {
        // Handle missing symbol gracefully or rethrow
        rethrow;
      }
    }
  }
  return tokens;
}

List<Token> _tokensToRpn(List<Token> tokens) {
  tokens.throwIfContainsInvalid();

  final operatorStack = Queue<OperatorToken>();
  final rpnSolveList = <Token>[];

  for (final token in tokens) {
    if (token is LiteralToken) {
      rpnSolveList.add(token);
    } else if (token is OperatorToken) {
      if (token.operator == Operator.RPAREN) {
        while (true) {
          if (operatorStack.isEmpty) {
            throw ArgumentError(
                'Mismatched Parentheses in token list\n\nSolve List:$rpnSolveList\n\nOperator Stack:$operatorStack');
          }
          final poppedOperator = operatorStack.removeLast();
          if (poppedOperator.operator == Operator.LPAREN) {
            break;
          } else {
            rpnSolveList.add(poppedOperator);
          }
          if (operatorStack.isEmpty) {
            break;
          }
        }
      } else {
        while (operatorStack.isNotEmpty && _precedenceCompare(token, operatorStack.last)) {
          rpnSolveList.add(operatorStack.removeLast());
        }
        operatorStack.addLast(token);
      }
    }
  }

  while (operatorStack.isNotEmpty) {
    rpnSolveList.add(operatorStack.removeLast());
  }

  return rpnSolveList;
}

bool _precedenceCompare(OperatorToken leftOpToken, OperatorToken rightOpToken) {
  switch (rightOpToken.associativity) {
    case Associativity.LEFT:
      return leftOpToken.precedence <= rightOpToken.precedence;
    case Associativity.RIGHT:
      return leftOpToken.precedence < rightOpToken.precedence;
    case Associativity.NONE:
      return false;
  }
}

class SolveResult {
  final double value;

  SolveResult(this.value);
}

SolveResult _shuntingYardSolve(List<Token> rpnSolveList) {
  rpnSolveList.throwIfContainsInvalid();

  final solveStack = Queue<Token>();

  for (final token in rpnSolveList) {
    if (token is LiteralToken) {
      solveStack.addLast(token);
    } else if (token is OperatorToken) {
      switch (token.numOperands) {
        case 2:
          final rhs = solveStack.removeLast();
          final lhs = solveStack.removeLast();

          if (lhs is! LiteralToken || rhs is! LiteralToken) {
            throw ArgumentError('Operator arguments were not both literals. lhs: ${lhs} rhs: ${rhs}.');
          }

          final double arithmeticResult;
          switch (token.operator) {
            case Operator.PLUS:
              arithmeticResult = lhs.value + rhs.value;
              break;
            case Operator.MINUS:
              arithmeticResult = lhs.value - rhs.value;
              break;
            case Operator.MULTIPLY:
              arithmeticResult = lhs.value * rhs.value;
              break;
            case Operator.DIVIDE:
              arithmeticResult = lhs.value / rhs.value;
              break;
            case Operator.EXPONENT:
              arithmeticResult = math.pow(lhs.value, rhs.value).toDouble();
              break;
            default:
              throw ArgumentError(
                  'Invalid operator provided: ${token.operator}, number of operands: ${token.numOperands}. Binary operator expected.');
          }

          solveStack.addLast(LiteralToken(arithmeticResult));
          break;

        case 1:
          final operand = solveStack.removeLast();

          if (operand is! LiteralToken) {
            throw ArgumentError('Operator argument was not a literal. operand: ${operand}.');
          }

          final double arithmeticResult;
          switch (token.operator) {
            case Operator.UNARY_PLUS:
              arithmeticResult = operand.value;
              break;
            case Operator.UNARY_MINUS:
              arithmeticResult = -operand.value;
              break;
            default:
              throw ArgumentError(
                  'Invalid operator provided: ${token.operator}, number of operands: ${token.numOperands}. Unary operator expected.');
          }

          solveStack.addLast(LiteralToken(arithmeticResult));
          break;

        default:
          throw ArgumentError('Invalid number of operands ${token.numOperands} for operator ${token.operator}');
      }
    }
  }

  if (solveStack.length != 1) {
    throw ArgumentError(
        'Final result was not a single value. Result stack count: ${solveStack.length}, Result stack values: ${solveStack.map((t) => t).join(',')}');
  }

  final finalToken = solveStack.single;
  if (finalToken is! LiteralToken) {
    throw StateError('Final token is not a LiteralToken');
  }

  return SolveResult(finalToken.value);
}

extension TokenListValidation on List<Token> {
  void throwIfContainsInvalid() {
    final invalidTokens = whereType<InvalidToken>().toList();
    if (invalidTokens.isNotEmpty) {
      final errors = invalidTokens
          .map((token) => ArgumentError('Invalid token: ${token.invalidShard} at position ${token.position}'))
          .toList();
      throw AggregateException('Parsing errors encountered:', errors.cast<Exception>());
    }
  }
}
