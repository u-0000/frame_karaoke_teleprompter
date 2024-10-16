import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

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

  // teleprompter data - timestamps and corresponding lyrics
  final List<Map<String, dynamic>> _lyrics = [];
  Timer? _timer;
  int _currentLine = -1;
  Duration _songDuration = Duration.zero;
  DateTime? _startTime;

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // Open the file picker for LRC files
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);

        // Read the LRC file content and parse it
        String content = await file.readAsString();
        _parseLRC(content);

        // Start playback and timer
        _startLyricsSync();
      } else {
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
      }
    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  /// Parse LRC content to extract timestamps and lyrics
  void _parseLRC(String content) {
    _lyrics.clear();
    _currentLine = -1;

    final RegExp regex = RegExp(r'\[(\d+):(\d+).(\d+)\](.*)');
    for (var line in content.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(match.group(3)!);
        final lyricsLine = match.group(4)?.trim() ?? '';

        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        _lyrics.add({
          'timestamp': timestamp,
          'text': TextUtils.wrapText(lyricsLine, 640, 4),
        });
      }
    }

    if (_lyrics.isNotEmpty) {
      _lyrics.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
    }
  }

  /// Start the timer to sync lyrics display
  void _startLyricsSync() {
    _startTime = DateTime.now();
    _currentLine = 0;

    _timer?.cancel();  // Cancel any previous timer
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final elapsed = DateTime.now().difference(_startTime!);

      if (_currentLine < _lyrics.length - 1) {
        final nextTimestamp = _lyrics[_currentLine + 1]['timestamp'] as Duration;
        if (elapsed >= nextTimestamp) {
          _currentLine++;
          _updateUI();
        }
      } else {
        _timer?.cancel();  // Stop when all lines are shown
      }
    });

    _updateUI();
  }

  /// Update UI with the current line
  void _updateUI() {
    if (_currentLine >= 0) {
      setState(() {
        // Update the displayed lyrics and send to Frame
        frame?.sendMessage(TxPlainText(
          msgCode: 0x0a,
          text: _lyrics[_currentLine]['text'],
        ));
      });
    }
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    _lyrics.clear();
    _currentLine = -1;
    _timer?.cancel();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Teleprompter',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Teleprompter'),
          actions: [getBatteryWidget()],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (x) async {
            // Allow manual navigation between lines
            if (x.velocity.pixelsPerSecond.dy > 0) {
              _currentLine > 0 ? --_currentLine : null;
            } else {
              _currentLine < _lyrics.length - 1 ? ++_currentLine : null;
            }
            if (_currentLine >= 0) {
              await frame!.sendMessage(TxPlainText(
                msgCode: 0x0a,
                text: _lyrics[_currentLine]['text'],
              ));
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
                  _currentLine >= 0 ? _lyrics[_currentLine]['text'] : 'Load an LRC file',
                  style: const TextStyle(fontSize: 24),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        floatingActionButton:
            getFloatingActionButtonWidget(const Icon(Icons.file_open), const Icon(Icons.close)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
