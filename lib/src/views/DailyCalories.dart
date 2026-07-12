import 'dart:async';

import 'package:calorie_tracker/generated/l10n/app_localizations.dart';
import 'package:calorie_tracker/src/constants/ColorConstants.dart';
import 'package:calorie_tracker/src/dto/CustomSymbolEntry.dart';
import 'package:calorie_tracker/src/dto/FoodItemEntry.dart';
import 'package:calorie_tracker/src/extensions/datetime_extensions.dart';
import 'package:calorie_tracker/src/helpers/DatabaseHelper.dart';
import 'package:calorie_tracker/src/widgets/SymbolBoldingTextEditingController.dart';
import 'package:flutter/material.dart';

class Entry {
  TextField textField;
  TextEditingController controller;
  int dbId;

  Entry({required this.textField, required this.controller, required this.dbId});

  void dispose() {
    controller.dispose();
    textField.focusNode?.dispose();
  }
}

class _CachedExpression {
  String expression;
  int commentIndex;
  double calories;

  _CachedExpression({required this.expression, required this.commentIndex, required this.calories});
}

class DailyCaloriesPage extends StatefulWidget {
  final void Function(int dailyCalories) setDailyCalories;
  final DateTime dateCurrentlyEditing;
  DailyCaloriesPage({super.key, required this.setDailyCalories, required this.dateCurrentlyEditing});

  @override
  State<DailyCaloriesPage> createState() => _DailyCaloriesPageState();
}

class _DailyCaloriesPageState extends State<DailyCaloriesPage> with WidgetsBindingObserver {
  List<Entry> entries = [];
  // for Date rollover to refresh to the current day
  DateTime? _today;
  Timer? _timer;

  DateTime get currentDateEditing => widget.dateCurrentlyEditing;

  final Map<int, _CachedExpression> cachedExpressions = Map();

  _CachedExpression evaluateExpression(FoodItemEntry entry, List<CustomSymbolEntry> userSymbols) {
    if (cachedExpressions.containsKey(entry.id) && entry.calorieExpression == cachedExpressions[entry.id]!.expression) {
      return cachedExpressions[entry.id]!;
    } else {
      final (:result, :commentIndex) = evaluateFoodItemWithCommentIndexAndSymbols(entry.calorieExpression, userSymbols);
      cachedExpressions[entry.id!] =
          _CachedExpression(expression: entry.calorieExpression, commentIndex: commentIndex, calories: result);
      return cachedExpressions[entry.id]!;
    }
  }

  Future<void> loadItems() async {
    final List<FoodItemEntry> foodItemEntries = await DatabaseHelper.instance.getFoodItems(currentDateEditing.dateOnly);
    final List<CustomSymbolEntry> userSymbols = await DatabaseHelper.instance.getAllUserSymbols();
    final getLabelText = (FoodItemEntry e) {
      if (e.calorieExpression != "" && double.tryParse(e.calorieExpression) == null) {
        return "= " + evaluateExpression(e, userSymbols).calories.round().toString();
      }
      return "";
    };
    widget.setDailyCalories(foodItemEntries.fold(
        0, (prev, cur) => prev + evaluateFoodItemWithCommentAndSymbols(cur.calorieExpression, userSymbols).round()));
    setState(() {
      entries = foodItemEntries.map((e) {
        final focusNode = FocusNode();
        focusNode.addListener(() {
          if (!focusNode.hasFocus) {
            loadItems();
          }
        });
        final controller = SymbolBoldingTextEditingController(
            userSymbols: userSymbols, commentIndex: evaluateExpression(e, userSymbols).commentIndex)
          ..text = e.calorieExpression;
        final labelText = getLabelText(e);
        return Entry(
          controller: controller,
          dbId: e.id!,
          textField: TextField(
            controller: controller,
            cursorColor: Colors.black,
            decoration: InputDecoration(
              label: labelText != ""
                  ? Container(
                      decoration: BoxDecoration(
                          color: ORANGE_FRUIT,
                          border: Border.all(width: 2, color: Colors.orange.shade800),
                          borderRadius: BorderRadius.all(Radius.circular(20))),
                      child: Padding(
                          padding: EdgeInsets.only(left: 10, right: 10),
                          child: Text(labelText, style: TextStyle(color: Theme.of(context).colorScheme.primary))),
                    )
                  : null,
              //labelText: labelText,
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueGrey)),
              border: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueGrey)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
            ),
            keyboardType: TextInputType.text,
            focusNode: focusNode,
            onChanged: (value) async {
              // force update
              await DatabaseHelper.instance.updateFoodEntry(
                  FoodItemEntry(id: e.id, calorieExpression: value, date: currentDateEditing.dateOnly));
              widget.setDailyCalories(await totalCalories());
              setState(() {});
            },
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                final lastEntry = entries.lastOrNull;
                if (lastEntry != null && lastEntry.textField.controller?.text == "") {
                  lastEntry.textField.focusNode?.requestFocus();
                } else {
                  addTextField();
                  focusNode.unfocus();
                }
              }
            },
            onEditingComplete: () {
              focusNode.unfocus();
            },
          ),
        );
      }).toList();
    });
  }

  Future<void> addTextField() async {
    await DatabaseHelper.instance.addFoodEntry(FoodItemEntry(calorieExpression: "", date: currentDateEditing.dateOnly));
    await loadItems();
    if (entries.isNotEmpty) {
      FocusScope.of(context).unfocus();
      entries[entries.length - 1].textField.focusNode?.requestFocus();
    }
  }

  Future<void> clearTextFields() async {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.clearListWarningTitle),
            content: Text(AppLocalizations.of(context)!.clearListWarningBody, style: TextStyle(color: Colors.red)),
            actions: [
              TextButton(
                child: Text(AppLocalizations.of(context)!.cancelButton),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(AppLocalizations.of(context)!.continueButton),
                onPressed: () async {
                  List<int> ids = entries.map((e) => e.dbId).toList();
                  for (int id in ids) {
                    DatabaseHelper.instance.deleteFoodEntry(id);
                  }
                  Navigator.of(context).pop();
                  await loadItems();
                },
              ),
            ],
          );
        });
  }

  Future<void> deleteTextField(int id) async {
    FocusScope.of(context).unfocus();
    await DatabaseHelper.instance.deleteFoodEntry(id);
    await loadItems();
  }

  Future<int> totalCalories() async {
    int total = 0;
    final userSymbols = await DatabaseHelper.instance.getAllUserSymbols();
    for (var item in entries) {
      total += evaluateFoodItemWithCommentAndSymbols(item.controller.text, userSymbols).round();
    }
    return total;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadItems();
    }
  }

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    setupDayRolloverTimer();
    WidgetsBinding.instance.addObserver(this);
    loadItems();
  }

  void setupDayRolloverTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      final now = DateTime.now();
      if (now.dateOnly != _today?.dateOnly) {
        print("here");
        loadItems();
        _today = DateTime.now();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (var entry in entries) {
      entry.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        // appBar: AppBar(
        //   title: Center(child: Text(AppLocalizations.of(context)!.dailyCalorieTotal(totalCalories()))),
        // ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: FractionalOffset.bottomCenter,
              colors: [Theme.of(context).colorScheme.surface, ORANGE_FRUIT],
              stops: const [0, 1],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 50, // Adjust the height as needed
                child: Container(
                  // Or any widget you want
                  child: Center(
                    child: Text(
                        "${currentDateEditing.dateOnly.day}/${currentDateEditing.dateOnly.month}/${currentDateEditing.dateOnly.year}"),
                  ),
                ),
              ),
              Positioned.fill(
                  child: SingleChildScrollView(
                      child: ListView.builder(
                physics: BouncingScrollPhysics(),
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  return Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 30 : 0),
                      child: ListTile(
                        title: entries[index].textField,
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () {
                            deleteTextField(entries[index].dbId);
                          },
                        ),
                      ));
                },
              )))
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.25)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                  color: Colors.green,
                  onPressed: () {
                    addTextField();
                  },
                  icon: const Icon(Icons.add_sharp)),
              IconButton(
                  color: Colors.red,
                  onPressed: () {
                    clearTextFields();
                  },
                  icon: const Icon(Icons.delete_forever))
            ],
          ),
        ));
  }
}
