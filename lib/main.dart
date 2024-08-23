import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:frame_teleprompter/frame_helper.dart';
import 'package:logging/logging.dart';

import 'simple_frame_app.dart';


void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  // teleprompter data - text and current chunk
  final List<String> _textChunks = [];
  int _currentLine = -1;

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // Open the file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);

        // Read the file content and split into lines
        String content = await file.readAsString();
        _textChunks.clear();

        // Update the UI
        setState(() {
          _textChunks.addAll(content.split('\n').map((chunk) => FrameHelper.wrapText(chunk, 640, 4)));
          _currentLine = 0;
        });
      }
      else {
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
      }
    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    _textChunks.clear();
    _currentLine = -1;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // FIXME remove
    currentState = ApplicationState.ready;
    return MaterialApp(
      title: 'Frame Teleprompter',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Teleprompter'),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (x) {
              if (x.velocity.pixelsPerSecond.dy > 0) {
                _currentLine > 0 ? --_currentLine : null;
              }
              else {
                _currentLine < _textChunks.length - 1 ? ++_currentLine : null;
              }
              if (_currentLine >= 0) {
                frame?.sendMessage(0x0a, utf8.encode(_textChunks[_currentLine]));
              }
              if (mounted) setState(() {});
            },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  _currentLine >= 0 ? _textChunks[_currentLine] : 'Load a file',
                  style: const TextStyle(fontSize: 24),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.file_open), const Icon(Icons.close)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
