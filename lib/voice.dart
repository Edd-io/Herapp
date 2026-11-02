import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictation and reading aloud, with the system's own speech (no server setup, works on the device).
class Voice extends ChangeNotifier {
  late final _stt = SpeechToText();
  late final _tts = FlutterTts()
    ..setCompletionHandler(_spoken)
    ..setCancelHandler(_spoken)
    ..setErrorHandler((_) => _spoken());
  var _ready = false;
  Object? reading; // what is being read aloud

  bool get listening => _stt.isListening;

  /// Listens, passing what is heard so far to [onWords]; false if speech recognition isn't available
  /// (refused, or no recognizer on this device).
  Future<bool> dictate(void Function(String words) onWords) async {
    _ready = _ready || await _stt.initialize(onStatus: (_) => notifyListeners(), onError: (_) => notifyListeners());
    if (!_ready) return false;
    await _stt.listen(
      onResult: (r) => onWords(r.recognizedWords),
      listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation, partialResults: true),
    );
    notifyListeners();
    return true;
  }

  Future<void> stopDictating() async {
    await _stt.stop();
    notifyListeners();
  }

  /// Reads [text] aloud for [what], or stops if [what] is being read.
  Future<void> read(Object what, String text) async {
    final again = identical(reading, what);
    await _tts.stop();
    reading = again ? null : what;
    notifyListeners();
    if (!again) await _tts.speak(speakable(text));
  }

  void _spoken() {
    reading = null;
    notifyListeners();
  }
}

final voice = Voice();

/// [markdown] as it reads aloud: no code, no markup, links by their text.
String speakable(String markdown) => markdown
    .replaceAll(RegExp(r'(`{3,}|~{3,})[\s\S]*?(\1|$)'), ' ')
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'https?://\S+'), '')
    .replaceAll(RegExp(r'^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+', multiLine: true), '')
    .replaceAll(RegExp(r'[*_`~|]'), '')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r' ?\n\s*'), '\n') // one line break between paragraphs
    .trim();
