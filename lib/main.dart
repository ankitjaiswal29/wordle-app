// A minimal Wordle-like demo with pause/resume, persistent resume, share score, and a time-limited mode.
// Drop into lib/main.dart of a new Flutter project.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const WordGuessApp());
}

class WordGuessApp extends StatelessWidget {
  const WordGuessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wordle app',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const GameHome(),
    );
  }
}

class GameState {
  final String target;
  final List<String> guesses;
  final bool finished;
  final bool timedMode;
  final int remainingSecs; // remaining seconds when saved

  GameState({
    required this.target,
    required this.guesses,
    required this.finished,
    required this.timedMode,
    required this.remainingSecs,
  });

  Map<String, dynamic> toJson() => {
    'target': target,
    'guesses': guesses,
    'finished': finished,
    'timedMode': timedMode,
    'remainingSecs': remainingSecs,
  };

  static GameState fromJson(Map<String, dynamic> j) => GameState(
    target: j['target'] as String,
    guesses: List<String>.from(j['guesses'] ?? []),
    finished: j['finished'] ?? false,
    timedMode: j['timedMode'] ?? false,
    remainingSecs: j['remainingSecs'] ?? 0,
  );
}

class GameHome extends StatefulWidget {
  const GameHome({super.key});

  @override
  State<GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<GameHome> with WidgetsBindingObserver {
  static const _saveKey = 'word_guess_state';
  final _controller = TextEditingController();
  final _sampleWords = ['APPLE', 'BRAVE', 'CRANE', 'DANCE', 'EPOCH', 'FLAME'];
  late String _target;
  List<String> _guesses = [];
  Timer? _timer;
  int _remainingSeconds = 300; // default time-limit for timed mode
  bool _timedMode = false;
  bool _paused = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _target = _sampleWords[(DateTime.now().millisecondsSinceEpoch % _sampleWords.length)];
    _loadState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Pause/resume when app lifecycle changes (optional)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // app backgrounded -> autosave
      _saveState();
    }
  }
  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final minutesStr = minutes.toString().padLeft(2, '0');
    final secondsStr = seconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_saveKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final gs = GameState.fromJson(decoded);
        setState(() {
          _target = gs.target;
          _guesses = gs.guesses;
          _finished = gs.finished;
          _timedMode = gs.timedMode;
          _remainingSeconds = gs.remainingSecs;
        });
        if (_timedMode && !_finished) {
          _startTimer(resume: true);
        }
        return;
      } catch (e) {
        // ignore parse errors and start new game
      }
    }
    // fresh game (already set target)
    _saveState();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final gs = GameState(
      target: _target,
      guesses: _guesses,
      finished: _finished,
      timedMode: _timedMode,
      remainingSecs: _remainingSeconds,
    );
    prefs.setString(_saveKey, jsonEncode(gs.toJson()));
  }

  void _startTimer({bool resume = false}) {
    _timer?.cancel();
    _paused = false;
    // if not resuming, reset remainingSeconds (example: 60 sec)
    if (!resume) _remainingSeconds = 300;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_paused) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _finished = true;
          _timer?.cancel();
          _showSnack('Time over! The word was $_target');
        }
      });
      _saveState();
    });
  }

  void _pauseGame() {
    setState(() {
      _paused = true;
    });
    _saveState();
  }

  void _resumeGame() {
    setState(() {
      _paused = false;
    });
    if (_timedMode && !_finished) _startTimer(resume: true);
    _saveState();
  }

  void _newGame({bool timed = false}) {
    setState(() {
      _target = _sampleWords[DateTime.now().millisecondsSinceEpoch % _sampleWords.length];
      _guesses = [];
      _finished = false;
      _timedMode = timed;
      _remainingSeconds = timed ? 60 : 0;
      _paused = false;
    });
    if (_timedMode) _startTimer(resume: false);
    else {
      _timer?.cancel();
    }
    _saveState();
  }

  void _submitGuess(String g) {
    if (_finished) return;
    final guess = g.trim().toUpperCase();
    if (guess.length != _target.length) {
      _showSnack('Guess must be ${_target.length} letters');
      return;
    }
    setState(() {
      _guesses.add(guess);
      if (guess == _target) {
        _finished = true;
        _timer?.cancel();
        _showSnack('You won in ${_guesses.length} tries!');
      } else if (_guesses.length >= 6) {
        _finished = true;
        _timer?.cancel();
        _showSnack('Out of tries! Word: $_target');
      }
    });
    _controller.clear();
    _saveState();
  }

  void _shareScore() {
    final txt = _finished
        ? 'I solved the word in ${_guesses.length} tries in Word Guess (sample)!'
        : 'Playing Word Guess — ${_guesses.length} tries so far.';
    Share.share(txt);
  }

  void _showSnack(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Widget _buildGrid() {
    final rows = List.generate(6, (r) {
      final guess = r < _guesses.length ? _guesses[r] : '';
      final letters = List.generate(_target.length, (c) {
        final ch = c < guess.length ? guess[c] : '';
        Color bg = Colors.grey.shade300;
        if (ch.isNotEmpty) {
          if (_target[c] == ch) bg = Colors.green;
          else if (_target.contains(ch)) bg = Colors.yellow.shade700;
          else bg = Colors.grey;
        }
        return Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(ch, style: const TextStyle(fontWeight: FontWeight.bold)),
        );
      });
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: letters);
    });
    return Column(children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Wordle app'),
        actions: [
          IconButton(
            tooltip: 'Share score',
            icon: const Icon(Icons.share),
            onPressed: _shareScore,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'new') _newGame(timed: false);
              if (v == 'new_timed') _newGame(timed: true);
              if (v == 'pause') _pauseGame();
              if (v == 'resume') _resumeGame();
              if (v == 'clear') _clearSaved();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('New Game')),
              const PopupMenuItem(value: 'new_timed', child: Text('New Timed Game (5 minutes)')),
              const PopupMenuItem(value: 'pause', child: Text('Pause')),
              const PopupMenuItem(value: 'resume', child: Text('Resume')),
              const PopupMenuItem(value: 'clear', child: Text('Clear saved state')),
            ],
          )
        ],
      ),
      body:SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_timedMode)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Time left: ${_formatTime(_remainingSeconds)}', style: const TextStyle(fontSize: 18)),
                  Text(_paused ? 'Paused' : 'Running'),
                ],
              ),
            const SizedBox(height: 12),
            _buildGrid(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'Enter guess'),
                    onSubmitted: (v) => _submitGuess(v),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => _submitGuess(_controller.text), child: const Text('Try'))
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                    onPressed: () {
                      if (!_timedMode) _startTimer(resume: false);
                      setState(() {
                        _timedMode = true;
                      });
                    },
                    child: const Text('Enable timed mode')),
                ElevatedButton(onPressed: _pauseGame, child: const Text('Pause')),
                ElevatedButton(onPressed: _resumeGame, child: const Text('Resume')),
                ElevatedButton(
                    onPressed: () {
                      _shareScore();
                    },
                    child: const Text('Share')),
              ],
            ),
            const SizedBox(height: 12),
            Text('Guesses: ${_guesses.length}  ${_finished ? "(finished)" : ""}'),
          ],
        ),
      ),
    );
  }

  Future<void> _clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saveKey);
    _showSnack('Saved state cleared. Starting new game.');
    _newGame(timed: false);
  }
}
