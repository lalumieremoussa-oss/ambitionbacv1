// 📁 lib/ia_pages/ia_lv2_coach.dart
// Coach IA pour LV2 (Allemand, Espagnol) — 100% AUDIO → AUDIO natif.
// Même architecture que IaAnCoachScreen (voir ce fichier pour les
// commentaires détaillés), paramétrée selon lv2Code.
//
// 🔧 CORRECTIFS appliqués (alignement sur ia_an_coach.dart) :
//  1. L'enregistrement se fait en PCM brut (.pcm) puis est converti en WAV
//     avec un header RIFF valide avant lecture/envoi. Avant, on écrivait
//     directement un fichier .wav alors que `record` avec
//     `AudioEncoder.pcm16bits` produit du PCM SANS header → le WAV était
//     corrompu et `extractPcmFromWav` pouvait échouer silencieusement.
//  2. Plus de double timeout : on relaie fidèlement CoachAiException (avec
//     son code) au lieu d'afficher un message générique "connexion".
//  3. try/catch sur _playAudioBubble pour ne plus planter silencieusement.
//  4. Sélection du professeur (équivalent Emma/Alex de l'anglais).
//
// ❌ Aucun FlutterTts. La voix entendue est toujours générée nativement par
// Gemini Live et renvoyée telle quelle par l'Edge Function "coach-ai".

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accueil/app_shared.dart';
import 'gemini_service.dart';

// ============================================================================
// ÉTATS DE LA MACHINE À ÉTATS
// ============================================================================
enum CoachState {
  idle,
  recording,
  recordedPreview,
  sending,
  aiThinking,
  aiSpeaking,
  error,
}

enum MessageSender { student, ai }

// ============================================================================
// SERVICE DE CRÉDIT
// ============================================================================
class CreditService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>> fetchCreditsFromServer(
      String matricule) async {
    try {
      final res = await _supabase
          .from('utilisateurs_premium')
          .select('premium, minutecoach')
          .eq('matricule', matricule)
          .maybeSingle();
      if (res == null)
        return {'exists': false, 'remaining': 0, 'premium': false};
      final bool isPremium = res['premium'] ?? false;
      final int used = (res['minutecoach'] as int?) ?? 0;
      final int max = isPremium
          ? ConfigCoach.defaultPremiumSeconds
          : ConfigCoach.defaultNonPremiumSeconds;
      final remaining = max - used;
      return {
        'exists': true,
        'remaining': remaining > 0 ? remaining : 0,
        'premium': isPremium
      };
    } catch (e) {
      debugPrint('Erreur fetchCreditsFromServer: $e');
      return {'exists': false, 'remaining': 0, 'premium': false};
    }
  }
}

// ============================================================================
// MODÈLE DE MESSAGE
// ============================================================================
class ChatMessage {
  final String id;
  final MessageSender sender;
  final String? audioPath;
  final int durationSeconds;
  final String? transcript;
  final DateTime timestamp;
  bool textRevealed;

  ChatMessage({
    required this.id,
    required this.sender,
    this.audioPath,
    this.durationSeconds = 0,
    this.transcript,
    required this.timestamp,
    this.textRevealed = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sender': sender.index,
        'audioPath': audioPath,
        'durationSeconds': durationSeconds,
        'transcript': transcript,
        'timestamp': timestamp.toIso8601String(),
        'textRevealed': textRevealed,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'],
        sender: MessageSender.values[map['sender']],
        audioPath: map['audioPath'],
        durationSeconds: map['durationSeconds'] ?? 0,
        transcript: map['transcript'],
        timestamp: DateTime.parse(map['timestamp']),
        textRevealed: map['textRevealed'] ?? false,
      );
}

// ============================================================================
// CONFIGURATION
// ============================================================================
class ConfigCoach {
  static const int defaultNonPremiumSeconds = 5 * 60;
  static const int defaultPremiumSeconds = 50 * 60;
  static const int sessionInactivityMinutes = 5;
  static const int inputSampleRate = 16000;
}

// ============================================================================
// ÉCRAN PRINCIPAL
// ============================================================================
class IaLv2CoachScreen extends StatefulWidget {
  final String matiereTitre;
  final String lv2Code; // 'DE' ou 'ES'

  const IaLv2CoachScreen({
    super.key,
    required this.matiereTitre,
    required this.lv2Code,
  });

  @override
  State<IaLv2CoachScreen> createState() => _IaLv2CoachScreenState();
}

class _IaLv2CoachScreenState extends State<IaLv2CoachScreen> {
  CoachState _currentState = CoachState.idle;

  late String _professor;
  late List<String> _professors; // coachs disponibles pour la langue
  String _level = 'Débutant';
  final List<String> _levels = [
    'Très débutant',
    'Débutant',
    'Intermédiaire',
    'Intermédiaire avancé',
    'Avancé',
  ];
  late String _languageCode; // 'DE' ou 'ES'
  String _systemPromptTemplate = '';

  List<ChatMessage> _messages = [];
  final List<ContextTurn> _recentContext = [];

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _previewPlayer = AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  String? _recordedAudioPath;
  int _recordedDurationSeconds = 0;
  bool _isPreviewPlaying = false;
  String? _currentlyPlayingMsgId;

  int _remainingSeconds = 0;
  String? _userMatricule;
  late Box _historyBox;
  Timer? _inactivityTimer;

  String? _audioStorageDir;

  StreamSubscription? _previewPlayerSubscription;
  StreamSubscription? _audioPlayerSubscription;

  @override
  void initState() {
    super.initState();
    _initLanguage();
    _initEngine();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    _previewPlayer.dispose();
    _scrollController.dispose();
    _previewPlayerSubscription?.cancel();
    _audioPlayerSubscription?.cancel();
    super.dispose();
  }

  void _initLanguage() {
    final code = widget.lv2Code.toUpperCase();
    _languageCode = code;
    if (code == 'DE') {
      _professors = ['Klaus', 'Anna'];
    } else if (code == 'ES') {
      _professors = ['Sofía', 'Carlos'];
    } else {
      _professors = ['Coach'];
    }
    _professor = _professors.first;
  }

  // ==========================================================================
  // INITIALISATION
  // ==========================================================================
  Future<void> _initEngine() async {
    await Hive.initFlutter();
    _historyBox =
        await Hive.openBox('${_languageCode.toLowerCase()}_coach_box_v2');

    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(
        '${appDir.path}/${_languageCode.toLowerCase()}_coach_audio_v2');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    _audioStorageDir = audioDir.path;

    try {
      _systemPromptTemplate =
          await rootBundle.loadString('assets/iac/$_languageCode.txt');
    } catch (_) {
      _systemPromptTemplate =
          "You are {professor}, a warm oral coach for $_languageCode at level {level}. Keep replies short and always end with a question.";
    }

    final prefs = await SharedPreferences.getInstance();
    _userMatricule = prefs.getString('matricule');

    _loadLocalHistory();

    await _refreshCreditsFromServer();

    _resetInactivityTimer();
  }

  String get _systemPrompt => _systemPromptTemplate
      .replaceAll('{professor}', _professor)
      .replaceAll('{level}', _level);

  // ==========================================================================
  // GESTION DU CRÉDIT
  // ==========================================================================
  Future<void> _refreshCreditsFromServer() async {
    if (_userMatricule == null) return;
    final result = await CreditService.fetchCreditsFromServer(_userMatricule!);
    if (mounted)
      setState(() => _remainingSeconds = result['remaining'] as int? ?? 0);
  }

  Future<bool> _checkCreditsBeforeAction({bool showError = true}) async {
    if (_userMatricule == null) {
      if (showError) _showErrorSnackBar('Utilisateur non identifié.');
      return false;
    }
    final result = await CreditService.fetchCreditsFromServer(_userMatricule!);
    if (!result['exists']) {
      if (showError)
        _showErrorSnackBar('Compte introuvable. Contactez le support.');
      setState(() => _remainingSeconds = 0);
      return false;
    }
    final remaining = result['remaining'] as int;
    setState(() => _remainingSeconds = remaining);
    if (remaining <= 0) {
      if (showError) _showCreditDialog();
      return false;
    }
    return true;
  }

  // ==========================================================================
  // HISTORIQUE LOCAL
  // ==========================================================================
  void _loadLocalHistory() {
    final rawList = _historyBox.get('messages', defaultValue: []) as List;
    final validMessages = <ChatMessage>[];
    for (var item in rawList) {
      final msg = ChatMessage.fromMap(Map<String, dynamic>.from(item));
      if (msg.audioPath != null && !File(msg.audioPath!).existsSync()) continue;
      validMessages.add(msg);
      if (msg.transcript != null && msg.transcript!.isNotEmpty) {
        _recentContext.add(ContextTurn(
          role: msg.sender == MessageSender.student ? 'user' : 'model',
          text: msg.transcript!,
        ));
      }
    }
    setState(() => _messages = validMessages);
  }

  void _saveHistory() {
    _historyBox.put('messages', _messages.map((m) => m.toMap()).toList());
  }

  // ==========================================================================
  // INACTIVITÉ
  // ==========================================================================
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
        Duration(minutes: ConfigCoach.sessionInactivityMinutes),
        _onInactivityTimeout);
  }

  Future<void> _onInactivityTimeout() async {
    await _audioPlayer.stop();
    await _previewPlayer.stop();
    if (mounted) setState(() => _currentState = CoachState.idle);
  }

  // ==========================================================================
  // CONVERSION PCM → WAV (header RIFF ajouté manuellement)
  //
  // 🔧 CORRECTIF : `record` avec AudioEncoder.pcm16bits écrit du PCM brut
  // SANS header. Avant, on sauvegardait directement ce PCM dans un fichier
  // .wav → WAV corrompu. On génère maintenant un vrai header RIFF.
  // ==========================================================================
  Future<void> _convertPcmToWav(String pcmPath, String wavPath) async {
    final pcmBytes = await File(pcmPath).readAsBytes();
    if (pcmBytes.isEmpty) throw Exception('Fichier PCM vide');

    final int sampleRate = ConfigCoach.inputSampleRate;
    final int numChannels = 1;
    final int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = pcmBytes.length;
    final int headerSize = 44;
    final int fileSize = headerSize + dataSize - 8;

    final Uint8List wavHeader = Uint8List(headerSize);
    int offset = 0;

    _writeString(wavHeader, offset, 'RIFF');
    offset += 4;
    _writeInt32(wavHeader, offset, fileSize, Endian.little);
    offset += 4;
    _writeString(wavHeader, offset, 'WAVE');
    offset += 4;

    _writeString(wavHeader, offset, 'fmt ');
    offset += 4;
    _writeInt32(wavHeader, offset, 16, Endian.little);
    offset += 4;
    _writeInt16(wavHeader, offset, 1, Endian.little);
    offset += 2;
    _writeInt16(wavHeader, offset, numChannels, Endian.little);
    offset += 2;
    _writeInt32(wavHeader, offset, sampleRate, Endian.little);
    offset += 4;
    _writeInt32(wavHeader, offset, byteRate, Endian.little);
    offset += 4;
    _writeInt16(wavHeader, offset, blockAlign, Endian.little);
    offset += 2;
    _writeInt16(wavHeader, offset, bitsPerSample, Endian.little);
    offset += 2;

    _writeString(wavHeader, offset, 'data');
    offset += 4;
    _writeInt32(wavHeader, offset, dataSize, Endian.little);
    offset += 4;

    final wavFile = File(wavPath);
    final sink = wavFile.openWrite();
    sink.add(wavHeader);
    sink.add(pcmBytes);
    await sink.close();

    try {
      await File(pcmPath).delete();
    } catch (_) {}
  }

  void _writeString(Uint8List bytes, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  void _writeInt32(Uint8List bytes, int offset, int value, Endian endian) {
    final b = ByteData(4)..setInt32(0, value, endian);
    bytes.setRange(offset, offset + 4, b.buffer.asUint8List());
  }

  void _writeInt16(Uint8List bytes, int offset, int value, Endian endian) {
    final b = ByteData(2)..setInt16(0, value, endian);
    bytes.setRange(offset, offset + 2, b.buffer.asUint8List());
  }

  // ==========================================================================
  // ENREGISTREMENT VOCAL — PCM16 mono 16kHz → converti en WAV
  // ==========================================================================
  Future<void> _handleMicButtonClick() async {
    _resetInactivityTimer();
    if (_currentState != CoachState.idle &&
        _currentState != CoachState.recording) return;

    final hasCredit = await _checkCreditsBeforeAction();
    if (!hasCredit) return;

    if (_currentState == CoachState.idle) {
      if (!await _recorder.hasPermission()) {
        _showErrorSnackBar('Permission du microphone non accordée.');
        return;
      }
      await _audioPlayer.stop();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // 🔧 On enregistre en .pcm (brut), la conversion en .wav valide se
      // fera à l'arrêt de l'enregistrement.
      final pcmPath = '$_audioStorageDir/user_speech_$timestamp.pcm';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: ConfigCoach.inputSampleRate,
          numChannels: 1,
        ),
        path: pcmPath,
      );
      setState(() {
        _currentState = CoachState.recording;
        _recordedAudioPath = null;
      });
    } else if (_currentState == CoachState.recording) {
      final rawPath = await _recorder.stop();
      if (rawPath == null) {
        setState(() => _currentState = CoachState.idle);
        return;
      }
      final rawFile = File(rawPath);
      if (!await rawFile.exists() || await rawFile.length() < 100) {
        _showErrorSnackBar('Enregistrement audio vide. Réessayez.');
        setState(() => _currentState = CoachState.idle);
        if (await rawFile.exists()) await rawFile.delete();
        return;
      }

      final bytesLen = await rawFile.length();
      int sec = (bytesLen / (ConfigCoach.inputSampleRate * 2)).round();
      if (sec < 1) sec = 1;

      if (sec > _remainingSeconds) {
        _showErrorSnackBar(
            'Crédit insuffisant pour cet enregistrement ($sec s). Il vous reste $_remainingSeconds s.');
        if (await rawFile.exists()) await rawFile.delete();
        setState(() => _currentState = CoachState.idle);
        return;
      }

      final wavPath =
          '$_audioStorageDir/user_speech_${DateTime.now().millisecondsSinceEpoch}.wav';
      try {
        await _convertPcmToWav(rawPath, wavPath);
      } catch (e) {
        _showErrorSnackBar('Erreur lors de la conversion audio: $e');
        if (await rawFile.exists()) await rawFile.delete();
        setState(() => _currentState = CoachState.idle);
        return;
      }

      setState(() {
        _currentState = CoachState.recordedPreview;
        _recordedAudioPath = wavPath;
        _recordedDurationSeconds = sec;
      });
    }
  }

  // ==========================================================================
  // PRÉVISUALISATION ET ENVOI
  // ==========================================================================
  Future<void> _sendRecordedAudio() async {
    _resetInactivityTimer();
    if (_recordedAudioPath == null ||
        _currentState != CoachState.recordedPreview) return;

    final hasCredit = await _checkCreditsBeforeAction();
    if (!hasCredit) return;

    if (_recordedDurationSeconds > _remainingSeconds) {
      _showErrorSnackBar('Crédit insuffisant pour cet enregistrement.');
      return;
    }

    final path = _recordedAudioPath!;
    final duration = _recordedDurationSeconds;

    setState(() {
      _currentState = CoachState.sending;
      _recordedAudioPath = null;
    });

    final studentMsg = ChatMessage(
      id: 's_audio_${DateTime.now().millisecondsSinceEpoch}',
      sender: MessageSender.student,
      audioPath: path,
      durationSeconds: duration,
      timestamp: DateTime.now(),
    );
    setState(() => _messages.add(studentMsg));
    _saveHistory();
    _scrollToBottom();

    await _processAiInteraction(
        studentAudioPath: path, studentMsgId: studentMsg.id);
  }

  void _discardPreview() {
    _resetInactivityTimer();
    if (_recordedAudioPath != null) {
      final file = File(_recordedAudioPath!);
      if (file.existsSync()) file.delete();
    }
    _previewPlayer.stop();
    setState(() {
      _currentState = CoachState.idle;
      _recordedAudioPath = null;
      _recordedDurationSeconds = 0;
      _isPreviewPlaying = false;
    });
  }

  Future<void> _playPreviewAudio() async {
    _resetInactivityTimer();
    if (_recordedAudioPath == null) {
      _showErrorSnackBar('Aucun fichier audio à écouter.');
      return;
    }
    try {
      if (_isPreviewPlaying) {
        await _previewPlayer.stop();
        setState(() => _isPreviewPlaying = false);
      } else {
        setState(() => _isPreviewPlaying = true);
        await _previewPlayer.play(DeviceFileSource(_recordedAudioPath!));
        _previewPlayerSubscription?.cancel();
        _previewPlayerSubscription =
            _previewPlayer.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _isPreviewPlaying = false);
        });
      }
    } catch (e) {
      setState(() => _isPreviewPlaying = false);
      _showErrorSnackBar('Impossible de lire l\'audio: $e');
    }
  }

  // ==========================================================================
  // APPEL GEMINI LIVE (audio → audio natif)
  //
  // 🔧 CORRECTIF : plus de `.timeout(30s)` ici — le timeout est géré une
  // seule fois dans CoachAiService (45s), qui est lui-même aligné avec le
  // délai maximum côté Edge Function. On relaie fidèlement le message
  // renvoyé par CoachAiException au lieu de le remplacer par un générique.
  // ==========================================================================
  Future<void> _processAiInteraction({
    required String studentAudioPath,
    required String studentMsgId,
  }) async {
    setState(() => _currentState = CoachState.aiThinking);

    try {
      if (_userMatricule == null) {
        throw CoachAiException('Utilisateur non identifié.');
      }

      final wavBytes = await File(studentAudioPath).readAsBytes();
      final pcmBytes =
          CoachAiService.extractPcmFromWav(Uint8List.fromList(wavBytes));

      final languageName = _languageCode == 'DE'
          ? 'german'
          : (_languageCode == 'ES' ? 'spanish' : 'english');

      final response = await CoachAiService.sendAudio(
        pcm16Mono16k: pcmBytes,
        systemPrompt: _systemPrompt,
        matricule: _userMatricule!,
        professor: _professor,
        level: _level,
        language: languageName,
        priorContext: _recentContext,
      );

      await _handleAiSuccess(response, studentMsgId);
    } on CoachAiException catch (e) {
      // Erreur identifiée par le service : on relaie son message tel quel.
      debugPrint('Erreur coach LV2 [${e.code}]: ${e.message}');
      setState(() => _currentState = CoachState.error);
      _showErrorSnackBar(e.message);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _currentState = CoachState.idle);
      });
    } catch (e, st) {
      // Erreur totalement inattendue (bug local).
      debugPrint('Erreur coach LV2 non-CoachAiException: $e\n$st');
      setState(() => _currentState = CoachState.error);
      _showErrorSnackBar('Erreur inattendue : $e');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _currentState = CoachState.idle);
      });
    }
  }

  Future<void> _handleAiSuccess(
      CoachAudioResponse response, String studentMsgId) async {
    setState(() => _remainingSeconds = response.remaining);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final aiPath = '$_audioStorageDir/ai_reply_$timestamp.wav';
    await File(aiPath).writeAsBytes(response.wavBytes);

    if (response.inputText != null && response.inputText!.isNotEmpty) {
      final idx = _messages.indexWhere((m) => m.id == studentMsgId);
      if (idx != -1) {
        _messages[idx] = ChatMessage(
          id: _messages[idx].id,
          sender: _messages[idx].sender,
          audioPath: _messages[idx].audioPath,
          durationSeconds: _messages[idx].durationSeconds,
          transcript: response.inputText,
          timestamp: _messages[idx].timestamp,
          textRevealed: _messages[idx].textRevealed,
        );
        _recentContext
            .add(ContextTurn(role: 'user', text: response.inputText!));
      }
    }

    final aiMsg = ChatMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      sender: MessageSender.ai,
      audioPath: aiPath,
      transcript: response.outputText,
      timestamp: DateTime.now(),
    );
    if (response.outputText != null && response.outputText!.isNotEmpty) {
      _recentContext
          .add(ContextTurn(role: 'model', text: response.outputText!));
    }
    while (_recentContext.length > 12) {
      _recentContext.removeAt(0);
    }

    setState(() => _messages.add(aiMsg));
    _saveHistory();
    _scrollToBottom();

    // 🔊 Lecture automatique de la voix native générée par Gemini.
    await _playAudioBubble(aiPath, aiMsg.id);
  }

  // ==========================================================================
  // LECTURE AUDIO
  //
  // 🔧 CORRECTIF : try/catch ajouté — avant, une erreur de lecture laissait
  // l'UI bloquée dans l'état `aiSpeaking` sans message à l'utilisateur.
  // ==========================================================================
  Future<void> _playAudioBubble(String path, String msgId) async {
    _resetInactivityTimer();
    await _audioPlayer.stop();

    setState(() {
      _currentState = CoachState.aiSpeaking;
      _currentlyPlayingMsgId = msgId;
    });

    try {
      await _audioPlayer.play(DeviceFileSource(path));
      _audioPlayerSubscription?.cancel();
      _audioPlayerSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _currentState = CoachState.idle;
            _currentlyPlayingMsgId = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _currentState = CoachState.idle;
        _currentlyPlayingMsgId = null;
      });
      _showErrorSnackBar('Impossible de lire la réponse du coach: $e');
    }
  }

  // ==========================================================================
  // UTILITAIRES
  // ==========================================================================
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showCreditDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crédit épuisé'),
        content: const Text(
            'Votre crédit de coaching vocal est épuisé. Rechargez votre compte pour continuer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
        ],
      ),
    );
  }

  // ==========================================================================
  // CHANGEMENT DE COACH / NIVEAU
  // ==========================================================================
  void _changeCoach(String newProf) async {
    if (_professor == newProf) return;
    await _audioPlayer.stop();
    setState(() => _professor = newProf);
  }

  void _changeLevel(String newLevel) async {
    if (_level == newLevel) return;
    await _audioPlayer.stop();
    setState(() => _level = newLevel);
  }

  void _showLevelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choisir votre niveau'),
        children: _levels
            .map((lvl) => SimpleDialogOption(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(lvl,
                        style: TextStyle(
                            fontWeight: _level == lvl
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _changeLevel(lvl);
                  },
                ))
            .toList(),
      ),
    );
  }

  // ==========================================================================
  // INTERFACE UTILISATEUR
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final langLabel = _languageCode == 'DE'
        ? 'allemand'
        : (_languageCode == 'ES' ? 'espagnol' : 'langue');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kMatiereGreen,
        foregroundColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              child: Text(_professor[0],
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_professor,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Coach d\'$langLabel • $_level',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            onSelected: (val) {
              if (val == 'level') {
                _showLevelDialog();
              } else {
                _changeCoach(val);
              }
            },
            itemBuilder: (ctx) => [
              ..._professors.map(
                (p) => PopupMenuItem(
                  value: p,
                  child: Text('Coach $p ${_professor == p ? "✓" : ""}'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'level', child: Text('Niveau : $_level')),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.graphic_eq, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('Voix native Gemini — 100% audio',
                        style: TextStyle(fontSize: 12, color: Colors.black87)),
                  ],
                ),
                Text(
                  '${_remainingSeconds ~/ 60} min ${_remainingSeconds % 60} s restantes',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: kAppOrange),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, idx) => _buildVoiceBubble(_messages[idx]),
            ),
          ),
          if (_currentState == CoachState.aiThinking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('🤖 $_professor écoute et réfléchit...',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          _buildBottomSection(),
        ],
      ),
    );
  }

  Widget _buildVoiceBubble(ChatMessage msg) {
    final isStudent = msg.sender == MessageSender.student;
    final align = isStudent ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isStudent ? kAppOrange.withOpacity(0.12) : Colors.grey.shade100;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.04)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_currentlyPlayingMsgId == msg.id
                        ? Icons.pause_circle
                        : Icons.play_circle),
                    color: isStudent ? kAppOrange : kMatiereGreen,
                    onPressed: msg.audioPath != null
                        ? () => _playAudioBubble(msg.audioPath!, msg.id)
                        : null,
                  ),
                  Text(
                    isStudent
                        ? '🎙️ ${msg.durationSeconds} s'
                        : '🔊 $_professor',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (msg.transcript != null && msg.transcript!.isNotEmpty)
                if (msg.textRevealed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(msg.transcript!,
                        style: const TextStyle(fontSize: 14)),
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    icon: const Icon(Icons.visibility,
                        size: 14, color: Colors.grey),
                    label: const Text('Afficher le texte',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    onPressed: () {
                      setState(() => msg.textRevealed = true);
                      _saveHistory();
                    },
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSection() {
    if (_currentState == CoachState.recordedPreview) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mic, color: kAppOrange),
                const SizedBox(width: 8),
                Text('🎙️ Message vocal — ${_recordedDurationSeconds}s',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                      _isPreviewPlaying
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      size: 30),
                  color: kAppOrange,
                  onPressed: _playPreviewAudio,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: _discardPreview),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.orange),
                  onPressed: () {
                    _discardPreview();
                    _handleMicButtonClick();
                  },
                ),
                ElevatedButton.icon(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: kMatiereGreen),
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text('Envoyer',
                      style: TextStyle(color: Colors.white)),
                  onPressed: _sendRecordedAudio,
                ),
              ],
            )
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentState == CoachState.recording)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                  SizedBox(width: 6),
                  Text('🔴 Enregistrement en cours... Touchez pour arrêter',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ],
              ),
            )
          else if (_currentState == CoachState.aiSpeaking)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text('🔊 Le coach parle...',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          GestureDetector(
            onTap: (_currentState == CoachState.idle ||
                    _currentState == CoachState.recording)
                ? _handleMicButtonClick
                : null,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: _currentState == CoachState.recording
                  ? Colors.red
                  : kAppOrange,
              child: Icon(
                _currentState == CoachState.recording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
