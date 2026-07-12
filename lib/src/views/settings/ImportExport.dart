import 'dart:convert';

import 'package:calorie_tracker/generated/l10n/app_localizations.dart';
import 'package:calorie_tracker/src/constants/ColorConstants.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dto/FoodItemEntry.dart';
import '../../helpers/DatabaseHelper.dart';

class ImportExport extends StatefulWidget {
  const ImportExport({super.key});

  @override
  State<ImportExport> createState() => _ImportExportState();
}

class _ImportExportState extends State<ImportExport> {
  static const MethodChannel _channel = MethodChannel("csv_downloader");

  static Future<({String? message, bool success})> downloadCsv(String csvContent) async {
    try {
      final String? filePath = await _channel.invokeMethod('downloadCsv', {'csvContent': csvContent});
      return (message: filePath, success: true);
    } catch (e) {
      return (message: "An error occurred when writing the csv. Exception: $e", success: false);
    }
  }

  /// shows localized overwrite dialogs using [context], return value is only logged so no need to translate
  static Future<({String message, bool success})> uploadCsv(BuildContext context) async {
    FilePickerResult? result = await FilePicker.pickFiles(
        dialogTitle: "Select your backup file", type: FileType.custom, withData: true, allowedExtensions: ["csv"]);
    if (result != null) {
      try {
        PlatformFile file = result.files.first;
        if (file.bytes != null) {
          showDialog(
              context: context,
              builder: (context) => AlertDialog(
                    title: Text(AppLocalizations.of(context)!.exportImportOverwriteWarningHeader,
                        style: TextStyle(color: Colors.red)),
                    content: Text(AppLocalizations.of(context)!.exportImportOverwriteWarningBody),
                    actions: [
                      TextButton(
                        style: Theme.of(context).textButtonTheme.style,
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text(AppLocalizations.of(context)!.cancelButton,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                      TextButton(
                        style: Theme.of(context).textButtonTheme.style,
                        child: Text(AppLocalizations.of(context)!.continueButton,
                            style: Theme.of(context).textTheme.bodyMedium),
                        onPressed: () {
                          showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                    title: Text(AppLocalizations.of(context)!.exportImportOverwriteWarning2Header,
                                        style: TextStyle(color: Colors.red)),
                                    content: Text(
                                      AppLocalizations.of(context)!.exportImportOverwriteWarning2Body,
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    actions: [
                                      TextButton(
                                        style: Theme.of(context).textButtonTheme.style,
                                        child: Text(AppLocalizations.of(context)!.cancelButton,
                                            style: Theme.of(context).textTheme.bodyMedium),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      TextButton(
                                        style: Theme.of(context).textButtonTheme.style,
                                        child: Text(AppLocalizations.of(context)!.exportImportOverwriteConfirm,
                                            style: Theme.of(context).textTheme.bodyMedium),
                                        onPressed: () async {
                                          // overwrite data (validate data, purge db table, write data)
                                          String csvString = utf8.decode(file.bytes!);
                                          final List<List<dynamic>> csvData = Csv().decode(csvString);
                                          // confirm all rows are valid
                                          for (final row in csvData) {
                                            if (row.length != 3) {
                                              showDialog(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                        title: Text(AppLocalizations.of(context)!
                                                            .exportImportDataMalformedErrorMsg),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () {
                                                                Navigator.of(context).pop();
                                                                Navigator.of(context).pop();
                                                                Navigator.of(context).pop();
                                                              },
                                                              child: Text(AppLocalizations.of(context)!.continueButton))
                                                        ],
                                                      ));
                                              return;
                                            }
                                          }
                                          // ids can be ignored because they are auto-incremented by the db anyway
                                          final List<FoodItemEntry> entries = csvData
                                              .skip(1)
                                              .map((row) => FoodItemEntry.fromMap({
                                                    "id": null, // auto-increment handles this already
                                                    "calorieExpression": row[1].toString(),
                                                    "date": DateTime.parse(row[2]).millisecondsSinceEpoch
                                                  }))
                                              .toList();

                                          await DatabaseHelper.instance.clearFoodEntriesTable();
                                          await DatabaseHelper.instance.batchAddFoodEntries(entries);

                                          Navigator.of(context).pop();
                                          Navigator.of(context).pop();
                                        },
                                      )
                                    ],
                                  ));
                        },
                      )
                    ],
                  ));

          return (message: "file had data, TODO", success: true);
        } else {
          return (message: "file was empty", success: false);
        }
      } catch (e) {
        return (message: "no file selected", success: false);
      }
    } else {
      return (message: "a file was not selected by the user", success: false);
    }
  }

  String _progressString = "";
  final _buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(150, 70)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3)))),
      backgroundColor: WidgetStatePropertyAll(ORANGE_FRUIT),
      textStyle: WidgetStatePropertyAll(TextStyle(color: Colors.black)));

  Future<void> exportData(BuildContext context) async {
    setState(() {
      _progressString = AppLocalizations.of(context)!.exportImportSavingMsg;
    });
    final DatabaseHelper db = await DatabaseHelper.instance;
    final List<List<dynamic>> csvRows = await db.getAllFoodItemsAsCsvRows();
    final String csvString = Csv().encode(csvRows);
    ({String? message, bool success}) result = await downloadCsv(csvString);
    if (result.success) {
      setState(() {
        _progressString = AppLocalizations.of(context)!.exportImportSavedFileMsg(result.message!);
      });
    } else {
      setState(() {
        _progressString = "Export unsuccessful. ${result.message}";
      });
    }
  }

  void importData(BuildContext context) async {
    final result = await uploadCsv(context);
    print(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.exportImportDataTitle),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
        body: Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 20),
            child: Column(
              children: [
                Text(AppLocalizations.of(context)!.exportImportText1),
                SizedBox(height: 10),
                Text(AppLocalizations.of(context)!.exportImportText2),
                SizedBox(height: 10),
                Text(AppLocalizations.of(context)!.exportImportText3),
                Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                          style: _buttonStyle,
                          onPressed: () => exportData(context),
                          child: Text(AppLocalizations.of(context)!.exportImportExportLabel,
                              style: TextStyle(color: Colors.black))),
                      TextButton(
                          style: _buttonStyle,
                          onPressed: () => importData(context),
                          child: Text(AppLocalizations.of(context)!.exportImportImportLabel,
                              style: TextStyle(color: Colors.black))),
                    ],
                  ),
                ),
                Padding(padding: EdgeInsets.only(top: 30), child: Text(_progressString))
              ],
            )));
  }
}
