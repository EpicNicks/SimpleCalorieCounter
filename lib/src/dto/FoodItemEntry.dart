import 'package:calorie_tracker/src/dto/CustomSymbolEntry.dart';
import 'package:calorie_tracker/src/internal/expression_parser/parse/Parser.dart';

import '../helpers/DatabaseHelper.dart';

class FoodItemEntry {
  final int? id;
  final String calorieExpression;
  final DateTime date;

  const FoodItemEntry({this.id, required this.calorieExpression, required this.date});

  factory FoodItemEntry.fromMap(Map<String, dynamic> json) => FoodItemEntry(
      id: json['id'],
      calorieExpression: json['calorieExpression'],
      date: DateTime.fromMillisecondsSinceEpoch(json['date']));

  Map<String, dynamic> toMap() => {
        'id': id,
        'calorieExpression': calorieExpression,
        'date': DateTime(date.year, date.month, date.day).millisecondsSinceEpoch
      };

  Map<String, dynamic> toMapForInsert() => {
        'calorieExpression': calorieExpression,
        'date': DateTime(date.year, date.month, date.day).millisecondsSinceEpoch
      };

  @override
  String toString() => "{ id: $id, calorieExpression: $calorieExpression, date: $date }";
}

bool isConstant(String calorieExpression) {
  return double.tryParse(calorieExpression) != null;
}

double evaluateFoodItem(String calorieExpression) {
  if (calorieExpression.isEmpty) {
    return 0;
  }
  try {
    calorieExpression = calorieExpression
        // allows for comma separated values while maintaining the semantics of a list total; fold(+, [1,2,3]) == fold([1+2+3 <6>])
        .replaceAll(",", "+");

    // figure this out
    // DatabaseHelper.instance.getAllUserSymbols().then((userSymbols) {
    //
    // });

    final (:result, comment: _) = parseWithComment(calorieExpression);
    // avoids division by zero
    return result.isFinite ? result : 0;
  } catch (e) {
    // retry the string from rtl until there is either a valid expression or null (allows implicit comments this way
    return evaluateFoodItem(calorieExpression.substring(0, calorieExpression.length - 1));
  }
}

double evaluateFoodItemWithCommentAndSymbols(String calorieExpression, List<CustomSymbolEntry> userSymbols) {
  if (calorieExpression.isEmpty) {
    return 0;
  }
  try {
    calorieExpression = calorieExpression.replaceAll(",", "+");
    final (:result, comment: _) = parseWithUserSymbolsAndComment(calorieExpression, userSymbols);
    return result.isFinite ? result : 0;
  } catch (e) {
    return 0;
  }
}

({double result, int commentIndex}) evaluateFoodItemWithCommentIndexAndSymbols(
    String calorieExpression, List<CustomSymbolEntry> userSymbols) {
  if (calorieExpression.isEmpty) {
    return (result: 0, commentIndex: -1);
  }
  try {
    calorieExpression = calorieExpression.replaceAll(",", "+");
    final (:result, :commentIndex) = parseWithUserSymbolsAndCommentIndex(calorieExpression, userSymbols);
    return result.isFinite ? (result: result, commentIndex: commentIndex) : (result: 0, commentIndex: -1);
  } catch (e) {
    return (result: 0, commentIndex: -1);
  }
}

Future<double> evaluateFoodItemWithCommentAndSymbolsAsync(String calorieExpression) async {
  final List<CustomSymbolEntry> userSymbols = await DatabaseHelper.instance.getAllUserSymbols();
  return evaluateFoodItemWithCommentAndSymbols(calorieExpression, userSymbols);
}

double evaluateFoodItemNoCommentWithSymbols(String calorieExpression, List<CustomSymbolEntry> userSymbols) {
  if (calorieExpression.isEmpty) {
    return 0;
  }
  try {
    calorieExpression = calorieExpression
        // allows for comma separated values while maintaining the semantics of a list total; fold(+, [1,2,3]) == fold([1+2+3 <6>])
        .replaceAll(",", "+");
    final double result = parseWithUserSymbols(calorieExpression, userSymbols);
    // avoids division by zero
    return result.isFinite ? result : 0;
  } catch (e) {
    return 0;
  }
}

Future<double> evaluateFoodItemNoComment(String calorieExpression) async {
  final List<CustomSymbolEntry> userSymbols = await DatabaseHelper.instance.getAllUserSymbols();
  return evaluateFoodItemNoCommentWithSymbols(calorieExpression, userSymbols);
}
