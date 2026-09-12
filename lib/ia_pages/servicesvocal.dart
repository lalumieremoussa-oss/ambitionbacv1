// 📁 lib/ia_pages/servicesvocal.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

// =============================================================================
// SERVICES VOCAL – ANGLAIS (et français)
// =============================================================================
//
// CORRECTIF IMPORTANT (voix coupée / seul le dernier segment est lu) :
// `_tts.speak()` de flutter_tts ne garantit, selon les plateformes, que le
// LANCEMENT de la synthèse, pas sa fin. Sans attendre explicitement la fin
// réelle (via le Completer complété par setCompletionHandler), un appel
// `speak()` suivant déclenche `_tts.stop()` sur l'énoncé encore en cours et
// le coupe. On attend donc désormais `_stopCompleter.future` (avec un
// timeout de sécurité) avant de considérer que `speak()` est terminé.

class ServicesVocal {
  ServicesVocal._();

  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _isSpeaking = false;
  static String _currentVoice = 'Alex';
  static List<dynamic> _availableVoices = [];
  static Completer<void>? _stopCompleter;

  // Sécurité anti-blocage si aucun handler ne se déclenche jamais
  // (moteur TTS silencieux sur certains appareils Android).
  static const Duration _speakTimeout = Duration(seconds: 30);

  static Future<void> _initialize() async {
    if (_initialized) return;

    try {
      // Langue par défaut (sera redéfinie dans speak)
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.43);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      try {
        final voices = await _tts.getVoices;
        if (voices is List) {
          _availableVoices = voices;
        }
      } catch (_) {
        _availableVoices = [];
      }

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _tts.setErrorHandler((message) {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  /// Lance la lecture ET attend la FIN RÉELLE de l'énoncé avant de renvoyer.
  /// C'est ce qui permet d'enchaîner plusieurs segments (ex: plusieurs
  /// phrases anglaises d'une même réponse IA) sans qu'un segment coupe
  /// le précédent.
  static Future<bool> speak({
    required String text,
    String voice = 'Alex',
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    try {
      await _initialize();

      // Déterminer si on parle français
      final bool isFrench = voice.toLowerCase() == 'fr';
      // Pour l'anglais, on distingue le genre
      final bool isFemale = !isFrench && voice.toLowerCase() == 'emma';
      _currentVoice = isFrench ? 'Français' : (isFemale ? 'Emma' : 'Alex');

      // On s'assure qu'aucune lecture précédente n'est active avant de
      // démarrer la nouvelle (sécurité, ne devrait plus arriver en
      // fonctionnement normal puisqu'on attend désormais la fin de chaque
      // énoncé avant de repartir).
      if (_isSpeaking) {
        try {
          await _tts.stop();
        } catch (_) {}
        _isSpeaking = false;
      }

      // Configuration spécifique selon la langue
      if (isFrench) {
        // Français : on force la locale et on laisse la voix par défaut du système
        await _tts.setLanguage('fr-FR');
        // On ne cherche pas de voix nommée, on utilise la voix système par défaut
      } else {
        // Anglais : configuration détaillée (Alex / Emma)
        await _tts.setLanguage('en-US');
        await _configureVoice(isFemale);
      }

      final completer = Completer<void>();
      _stopCompleter = completer;
      _isSpeaking = true;

      await _tts.speak(cleanText);

      // ⏳ Attente de la fin RÉELLE de la lecture (handler complete/cancel/
      // error), avec un timeout de sécurité pour ne jamais bloquer
      // indéfiniment si le moteur TTS ne déclenche aucun handler.
      try {
        await completer.future.timeout(_speakTimeout);
      } on TimeoutException {
        _isSpeaking = false;
        if (kDebugMode) {
          debugPrint('ServicesVocal.speak timeout: pas de fin détectée.');
        }
      }

      return true;
    } catch (e) {
      _isSpeaking = false;
      if (kDebugMode) {
        debugPrint('ServicesVocal.speak error: $e');
      }
      return false;
    }
  }

  // (La méthode _configureVoice reste identique pour l'anglais)
  static Future<void> _configureVoice(bool isFemale) async {
    try {
      await _tts.setLanguage('en-US');
    } catch (_) {}

    if (_availableVoices.isEmpty) return;

    dynamic selectedVoice;

    final List<String> genderKeywords = isFemale
        ? [
            'female',
            'woman',
            'girl',
            'samantha',
            'victoria',
            'emma',
            'siri',
            'alexa'
          ]
        : ['male', 'man', 'boy', 'alex', 'daniel', 'david', 'john', 'michael'];

    final englishVoices = _availableVoices.where((voice) {
      final map = _voiceToMap(voice);
      final locale =
          (map['locale'] ?? map['language'] ?? '').toString().toLowerCase();
      return locale.contains('en') || locale.contains('english');
    }).toList();

    if (englishVoices.isNotEmpty) {
      for (final voice in englishVoices) {
        final map = _voiceToMap(voice);
        final name = (map['name'] ?? '').toString().toLowerCase();
        final locale = (map['locale'] ?? '').toString().toLowerCase();
        final combined = '$name $locale';

        for (final keyword in genderKeywords) {
          if (combined.contains(keyword)) {
            selectedVoice = voice;
            break;
          }
        }
        if (selectedVoice != null) break;
      }
    }

    selectedVoice ??=
        englishVoices.isNotEmpty ? englishVoices.first : _availableVoices.first;

    final map = _voiceToMap(selectedVoice);
    final name = map['name']?.toString();
    final locale = map['locale']?.toString() ?? map['language']?.toString();

    try {
      if (name != null &&
          name.trim().isNotEmpty &&
          locale != null &&
          locale.trim().isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': locale});
      } else if (name != null && name.trim().isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': 'en-US'});
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _voiceToMap(dynamic voice) {
    if (voice is Map) {
      return Map<String, dynamic>.from(voice);
    }
    return {
      'name': voice.toString(),
      'locale': 'en-US',
    };
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    final completer = _stopCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  static Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ServicesVocal.pause error: $e');
      }
    }
  }

  static Future<void> resume() async {
    try {
      await _tts.speak('');
    } catch (_) {}
  }

  static Future<bool> testVoice({String voice = 'Alex'}) async {
    return speak(text: 'Hello. This is your English teacher.', voice: voice);
  }

  static bool get isSpeaking => _isSpeaking;
  static String get currentVoice => _currentVoice;

  static Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      await _initialize();
      return _availableVoices.map((voice) => _voiceToMap(voice)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    _initialized = false;
    _availableVoices = [];
    _stopCompleter = null;
  }
}
// =============================================================================
// SERVICES VOCAL – ALLEMAND
// =============================================================================

class ServicesVocalDe {
  ServicesVocalDe._();

  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _isSpeaking = false;
  static String _currentVoice = 'Anna';
  static List<dynamic> _availableVoices = [];
  static Completer<void>? _stopCompleter;

  static const Duration _speakTimeout = Duration(seconds: 30);

  static Future<void> _initialize() async {
    if (_initialized) return;

    try {
      await _tts.setLanguage('de-DE');
      await _tts.setSpeechRate(0.43);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      try {
        final voices = await _tts.getVoices;
        if (voices is List) {
          _availableVoices = voices;
        }
      } catch (_) {
        _availableVoices = [];
      }

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _tts.setErrorHandler((message) {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  static Future<bool> speak({
    required String text,
    String voice = 'Anna',
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    try {
      await _initialize();

      final bool isFemale = voice.toLowerCase() == 'anna';
      _currentVoice = isFemale ? 'Anna' : 'Mark';

      if (_isSpeaking) {
        try {
          await _tts.stop();
        } catch (_) {}
        _isSpeaking = false;
      }

      await _configureVoice(isFemale);

      final completer = Completer<void>();
      _stopCompleter = completer;
      _isSpeaking = true;

      await _tts.speak(cleanText);

      try {
        await completer.future.timeout(_speakTimeout);
      } on TimeoutException {
        _isSpeaking = false;
        if (kDebugMode) {
          debugPrint('ServicesVocalDe.speak timeout: pas de fin détectée.');
        }
      }

      return true;
    } catch (e) {
      _isSpeaking = false;
      if (kDebugMode) {
        debugPrint('ServicesVocalDe.speak error: $e');
      }
      return false;
    }
  }

  static Future<void> _configureVoice(bool isFemale) async {
    try {
      await _tts.setLanguage('de-DE');
    } catch (_) {}

    if (_availableVoices.isEmpty) return;

    dynamic selectedVoice;

    final List<String> genderKeywords = isFemale
        ? ['female', 'woman', 'girl', 'anna', 'marlene', 'sophie', 'claudia']
        : ['male', 'man', 'boy', 'mark', 'jonas', 'lukas', 'paul'];

    final germanVoices = _availableVoices.where((voice) {
      final map = _voiceToMap(voice);
      final locale =
          (map['locale'] ?? map['language'] ?? '').toString().toLowerCase();
      return locale.contains('de') || locale.contains('german');
    }).toList();

    if (germanVoices.isNotEmpty) {
      for (final voice in germanVoices) {
        final map = _voiceToMap(voice);
        final name = (map['name'] ?? '').toString().toLowerCase();
        final locale = (map['locale'] ?? '').toString().toLowerCase();
        final combined = '$name $locale';

        for (final keyword in genderKeywords) {
          if (combined.contains(keyword)) {
            selectedVoice = voice;
            break;
          }
        }
        if (selectedVoice != null) break;
      }
    }

    selectedVoice ??=
        germanVoices.isNotEmpty ? germanVoices.first : _availableVoices.first;

    final map = _voiceToMap(selectedVoice);
    final name = map['name']?.toString();
    final locale = map['locale']?.toString() ?? map['language']?.toString();

    try {
      if (name != null &&
          name.trim().isNotEmpty &&
          locale != null &&
          locale.trim().isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': locale});
      } else if (name != null && name.trim().isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': 'de-DE'});
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _voiceToMap(dynamic voice) {
    if (voice is Map) {
      return Map<String, dynamic>.from(voice);
    }
    return {
      'name': voice.toString(),
      'locale': 'de-DE',
    };
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    final completer = _stopCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  static Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ServicesVocalDe.pause error: $e');
      }
    }
  }

  static Future<void> resume() async {
    try {
      await _tts.speak('');
    } catch (_) {}
  }

  static Future<bool> testVoice({String voice = 'Anna'}) async {
    return speak(text: 'Hallo, ich bin dein Deutschlehrer.', voice: voice);
  }

  static bool get isSpeaking => _isSpeaking;
  static String get currentVoice => _currentVoice;

  static Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      await _initialize();
      return _availableVoices.map((voice) => _voiceToMap(voice)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    _initialized = false;
    _availableVoices = [];
    _stopCompleter = null;
  }
}

// =============================================================================
// SERVICES VOCAL – ESPAGNOL
// =============================================================================

class ServicesVocalEs {
  ServicesVocalEs._();

  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _isSpeaking = false;
  static String _currentVoice = 'Lola';
  static List<dynamic> _availableVoices = [];
  static Completer<void>? _stopCompleter;

  static const Duration _speakTimeout = Duration(seconds: 30);

  static Future<void> _initialize() async {
    if (_initialized) return;

    try {
      await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.43);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      try {
        final voices = await _tts.getVoices;
        if (voices is List) {
          _availableVoices = voices;
        }
      } catch (_) {
        _availableVoices = [];
      }

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _tts.setErrorHandler((message) {
        _isSpeaking = false;
        final completer = _stopCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });

      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  static Future<bool> speak({
    required String text,
    String voice = 'Lola',
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    try {
      await _initialize();

      final bool isFemale = voice.toLowerCase() == 'lola';
      _currentVoice = isFemale ? 'Lola' : 'Diego';

      if (_isSpeaking) {
        try {
          await _tts.stop();
        } catch (_) {}
        _isSpeaking = false;
      }

      await _configureVoice(isFemale);

      final completer = Completer<void>();
      _stopCompleter = completer;
      _isSpeaking = true;

      await _tts.speak(cleanText);

      try {
        await completer.future.timeout(_speakTimeout);
      } on TimeoutException {
        _isSpeaking = false;
        if (kDebugMode) {
          debugPrint('ServicesVocalEs.speak timeout: pas de fin détectée.');
        }
      }

      return true;
    } catch (e) {
      _isSpeaking = false;
      if (kDebugMode) {
        debugPrint('ServicesVocalEs.speak error: $e');
      }
      return false;
    }
  }

  static Future<void> _configureVoice(bool isFemale) async {
    try {
      await _tts.setLanguage('es-ES');
    } catch (_) {}

    if (_availableVoices.isEmpty) return;

    dynamic selectedVoice;

    final List<String> genderKeywords = isFemale
        ? ['female', 'woman', 'girl', 'lola', 'monica', 'carmen', 'julia']
        : ['male', 'man', 'boy', 'diego', 'juan', 'carlos', 'manuel'];

    final spanishVoices = _availableVoices.where((voice) {
      final map = _voiceToMap(voice);
      final locale =
          (map['locale'] ?? map['language'] ?? '').toString().toLowerCase();
      return locale.contains('es') || locale.contains('spanish');
    }).toList();

    if (spanishVoices.isNotEmpty) {
      for (final voice in spanishVoices) {
        final map = _voiceToMap(voice);
        final name = (map['name'] ?? '').toString().toLowerCase();
        final locale = (map['locale'] ?? '').toString().toLowerCase();
        final combined = '$name $locale';

        for (final keyword in genderKeywords) {
          if (combined.contains(keyword)) {
            selectedVoice = voice;
            break;
          }
        }
        if (selectedVoice != null) break;
      }
    }

    selectedVoice ??=
        spanishVoices.isNotEmpty ? spanishVoices.first : _availableVoices.first;

    final map = _voiceToMap(selectedVoice);
    final name = map['name']?.toString();
    final locale = map['locale']?.toString() ?? map['language']?.toString();

    try {
      if (name != null &&
          name.trim().isNotEmpty &&
          locale != null &&
          locale.trim().isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': locale});
      } else if (name != null && name.trim().isNotEmpty) {
        await _tts.setVoice({'name': name, 'locale': 'es-ES'});
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _voiceToMap(dynamic voice) {
    if (voice is Map) {
      return Map<String, dynamic>.from(voice);
    }
    return {
      'name': voice.toString(),
      'locale': 'es-ES',
    };
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    final completer = _stopCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  static Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ServicesVocalEs.pause error: $e');
      }
    }
  }

  static Future<void> resume() async {
    try {
      await _tts.speak('');
    } catch (_) {}
  }

  static Future<bool> testVoice({String voice = 'Lola'}) async {
    return speak(text: 'Hola, soy tu profesor de español.', voice: voice);
  }

  static bool get isSpeaking => _isSpeaking;
  static String get currentVoice => _currentVoice;

  static Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      await _initialize();
      return _availableVoices.map((voice) => _voiceToMap(voice)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    _initialized = false;
    _availableVoices = [];
    _stopCompleter = null;
  }
}
