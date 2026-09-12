// 📁 lib/ia_pages/ia_an_conversation.dart
//
// Écran de CONVERSATION RÉELLE avec Prof IA (anglais).
// Fil de discussion continu, entrée texte OU vocale, réponse IA en JSON
// segmenté affichée en texte + lue automatiquement en audio.
//
// RÈGLE AUDIO (v2) : seule la langue cible (anglais) est vocalisée.
// Le français reste du texte à l'écran (explication pédagogique),
// il n'est jamais lu automatiquement.
//
// Dépendances à ajouter dans pubspec.yaml :
//   speech_to_text: ^6.6.0
// + permissions micro (Android: RECORD_AUDIO, iOS: NSMicrophoneUsageDescription
// + NSSpeechRecognitionUsageDescription).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'ia_services.dart';
import 'servicesvocal.dart';
import '../login/inscription_view.dart';

class IaAnConversationPage extends StatefulWidget {
  final String? matiereTitre;

  const IaAnConversationPage({
    super.key,
    this.matiereTitre,
  });

  @override
  State<IaAnConversationPage> createState() => _IaAnConversationPageState();
}

// =============================================================================
// MODÈLES
// =============================================================================

class _ChatMessage {
  final String role; // 'user' | 'ia'
  final String? text; // texte brut si role == user
  final Map<String, dynamic>? data; // JSON complet si role == ia
  final DateTime date;

  _ChatMessage({
    required this.role,
    this.text,
    this.data,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'role': role,
        'text': text,
        'data': data,
        'date': date.toIso8601String(),
      };

  static _ChatMessage fromMap(Map map) {
    return _ChatMessage(
      role: map['role']?.toString() ?? 'user',
      text: map['text']?.toString(),
      data: map['data'] is Map ? Map<String, dynamic>.from(map['data']) : null,
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class _IaAnConversationPageState extends State<IaAnConversationPage>
    with SingleTickerProviderStateMixin {
  // =========================================================================
  // CONSTANTES
  // =========================================================================

  static const String _historyBoxName = 'iaHistoryBox';
  static const String _threadKey = 'an_conversation_thread';

  static const String _voiceKey = 'prof_ia_anglais_voice';
  static const String _defaultVoice = 'Alex';

  static const String _promptKey = 'AN2';

  // Palette (identique au reste de l'app)
  static const Color _blue900 = Color(0xFF061A40);
  static const Color _blue800 = Color(0xFF0B2D63);
  static const Color _blue700 = Color(0xFF104F9E);
  static const Color _blue600 = Color(0xFF1677D2);
  static const Color _cyan = Color(0xFF4FD9FF);

  static const Color _background = Color(0xFFF5F9FF);
  static const Color _text = Color(0xFF10213A);
  static const Color _secondary = Color(0xFF68778C);
  static const Color _red = Color(0xFFD94747);

  static const List<String> _starterTopics = [
    "Let's talk about counting",
    "Explique-moi une leçon",
    "Let's talk about my day",
    "Aide-moi à corriger une phrase",
  ];

  // =========================================================================
  // CONTROLLERS
  // =========================================================================

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  final stt.SpeechToText _speech = stt.SpeechToText();

  // =========================================================================
  // ÉTAT
  // =========================================================================

  bool _isSending = false;
  bool _isListening = false;
  bool _speechReady = false;
  String? _errorMessage;

  String _voice = _defaultVoice;
  String _niveauEstime = 'Débutant';

  final List<_ChatMessage> _messages = [];
  final Set<String> _speakingKeys = <String>{};

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadVoice(),
      _loadThread(),
      _initSpeech(),
    ]);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  // =========================================================================
  // VOIX
  // =========================================================================

  Future<void> _loadVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_voiceKey) ?? _defaultVoice;
      if (!mounted) return;
      setState(() => _voice = saved == 'Emma' ? 'Emma' : 'Alex');
    } catch (_) {}
  }

  Future<void> _setVoice(String voice) async {
    final selected = voice == 'Emma' ? 'Emma' : 'Alex';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_voiceKey, selected);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _voice = selected);
  }

  // =========================================================================
  // RECONNAISSANCE VOCALE (STT)
  // =========================================================================

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              setState(() => _isListening = false);
              _autoSendIfDictated();
            }
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (mounted) setState(() {});
    } catch (_) {
      _speechReady = false;
    }
  }

  void _autoSendIfDictated() {
    final text = _inputController.text.trim();
    if (text.isNotEmpty) {
      _sendMessage();
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      _autoSendIfDictated();
      return;
    }

    if (!_speechReady) {
      _showMessage('Micro indisponible sur cet appareil.');
      return;
    }

    setState(() {
      _isListening = true;
      _inputController.clear();
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _inputController.text = result.recognizedWords;
        });
      },
    );
  }

  // =========================================================================
  // HISTORIQUE (FIL DE DISCUSSION CONTINU)
  // =========================================================================

  Future<String?> _getUserMatricule() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('matricule');
  }

  Future<void> _loadThread() async {
    try {
      if (!Hive.isBoxOpen(_historyBoxName)) {
        await Hive.openBox(_historyBoxName);
      }
      final box = Hive.box(_historyBoxName);
      final matricule = await _getUserMatricule();
      final key = _threadStorageKey(matricule);
      final raw = box.get(key);
      if (raw is List) {
        final loaded =
            raw.whereType<Map>().map((m) => _ChatMessage.fromMap(m)).toList();
        if (!mounted) return;
        setState(() {
          _messages
            ..clear()
            ..addAll(loaded);
          final lastIa = _messages.lastWhere(
            (m) => m.role == 'ia',
            orElse: () => _ChatMessage(role: '', date: DateTime.now()),
          );
          if (lastIa.data != null) {
            _niveauEstime =
                lastIa.data!['niveau_estime']?.toString() ?? _niveauEstime;
          }
        });
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom(animated: false));
      }
    } catch (_) {}
  }

  Future<void> _saveThread() async {
    try {
      if (!Hive.isBoxOpen(_historyBoxName)) {
        await Hive.openBox(_historyBoxName);
      }
      final box = Hive.box(_historyBoxName);
      final matricule = await _getUserMatricule();
      final key = _threadStorageKey(matricule);
      final serialized = _messages.map((m) => m.toMap()).toList();
      await box.put(key, serialized);
    } catch (_) {}
  }

  String _threadStorageKey(String? matricule) {
    return matricule == null || matricule.isEmpty
        ? _threadKey
        : '${_threadKey}_$matricule';
  }

  Future<void> _resetConversation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recommencer la discussion ?'),
        content: const Text(
            'Ton historique de conversation avec Prof IA sera effacé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _messages.clear();
      _errorMessage = null;
    });
    await _saveThread();
  }

  // =========================================================================
  // QUOTA (10 requêtes essai)
  // =========================================================================
  //
  // IMPORTANT : l'incrément de `iaacces` est géré UNIQUEMENT côté Edge function.
  // Le client Flutter se contente de LIRE cette valeur pour afficher/contrôler
  // la limite d'essai. Il ne doit jamais la modifier lui-même, sinon le
  // compteur serait incrémenté deux fois (une fois par l'Edge, une fois ici).

  Future<int> _getRemainingCalls() async {
    final matricule = await _getUserMatricule();
    if (matricule == null || matricule.isEmpty) return -1;
    try {
      final response = await Supabase.instance.client
          .from('utilisateurs_premium')
          .select('iaacces')
          .eq('matricule', matricule)
          .maybeSingle();
      if (response == null) return -1;
      final int iaacces = response['iaacces'] as int? ?? 0;
      return 10 - iaacces;
    } catch (e) {
      debugPrint('Erreur quota conversation : $e');
      return -1;
    }
  }

  Future<void> _showLimitDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Limite d’essai atteinte'),
        content:
            const Text('Tu as utilisé tes 10 échanges gratuits avec Prof IA. '
                'Passe à Premium pour continuer la conversation sans limite.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue700),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InscriptionView(),
                ),
              );
            },
            child: const Text('Découvrir Premium',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // CONSTRUCTION DU CONTEXTE (2 derniers échanges + message actuel)
  // =========================================================================

  String _plainTextOf(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    final segments = data['segments'];
    if (segments is List) {
      for (final seg in segments) {
        if (seg is Map) {
          final t = seg['texte']?.toString().trim() ?? '';
          if (t.isNotEmpty) buffer.write('$t ');
        }
      }
    }
    final question = data['question_suivante'];
    if (question is Map) {
      final t = question['texte']?.toString().trim() ?? '';
      if (t.isNotEmpty) buffer.write(t);
    }
    return buffer.toString().trim();
  }

  String _buildPromptWithContext(String currentMessage) {
    final pairs = <String>[];
    var i = _messages.length - 1;
    var pairsFound = 0;
    while (i >= 1 && pairsFound < 2) {
      final iaMsg = _messages[i];
      final userMsg = _messages[i - 1];
      if (iaMsg.role == 'ia' && userMsg.role == 'user') {
        final iaText = iaMsg.data != null ? _plainTextOf(iaMsg.data!) : '';
        pairs.insert(
          0,
          'Élève : ${userMsg.text ?? ''}\nProf IA : $iaText',
        );
        pairsFound++;
        i -= 2;
      } else {
        i -= 1;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('MESSAGE ACTUEL');
    buffer.writeln(currentMessage);
    if (pairs.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('CONTEXTE PRÉCÉDENT');
      for (var j = 0; j < pairs.length; j++) {
        buffer.writeln('ÉCHANGE ${j + 1} :');
        buffer.writeln(pairs[j]);
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  // =========================================================================
  // ENVOI DU MESSAGE
  // =========================================================================

  Future<void> _sendMessage([String? forcedText]) async {
    final text = (forcedText ?? _inputController.text).trim();
    if (text.isEmpty) {
      _showMessage('Écris ou dis quelque chose à Prof IA.');
      return;
    }
    if (_isSending) return;

    final remaining = await _getRemainingCalls();
    if (remaining == -1) {
      _showMessage('Connexion impossible. Vérifie ta connexion.');
      return;
    }
    if (remaining <= 0) {
      await _showLimitDialog();
      return;
    }

    final prompt = _buildPromptWithContext(text);

    setState(() {
      _messages
          .add(_ChatMessage(role: 'user', text: text, date: DateTime.now()));
      _inputController.clear();
      _isSending = true;
      _errorMessage = null;
    });
    await _saveThread();
    _scrollToBottom();

    try {
      final response = await IaService().chatCompletion(
        promptKey: _promptKey,
        userPrompt: prompt,
        temperature: 0.4,
        maxTokens: 1500,
      );

      final rawText = _extractResponseText(response);
      if (rawText.trim().isEmpty) {
        throw Exception('Prof IA n’a retourné aucune réponse.');
      }

      final cleaned = _cleanJsonResponse(rawText);
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) {
        throw Exception('Réponse IA invalide (pas un objet JSON).');
      }
      final data = Map<String, dynamic>.from(decoded);
      _validateConversation(data);

      if (!mounted) return;
      setState(() {
        _messages
            .add(_ChatMessage(role: 'ia', data: data, date: DateTime.now()));
        _niveauEstime = data['niveau_estime']?.toString() ?? _niveauEstime;
        _isSending = false;
      });

      // L'incrément du quota est géré côté Edge function (voir plus haut).

      await _saveThread();
      _scrollToBottom();

      final msgKey = 'ia_${_messages.length - 1}';
      unawaited(_playMessageAudio(data, msgKey));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  // =========================================================================
  // EXTRACTION / NETTOYAGE / VALIDATION JSON
  // =========================================================================

  String _extractResponseText(dynamic response) {
    if (response == null) return '';
    if (response is String) return response;
    if (response is Map) {
      final map = Map<String, dynamic>.from(response);
      final candidates = [
        map['text'],
        map['content'],
        map['response'],
        map['result'],
        map['output'],
      ];
      for (final candidate in candidates) {
        if (candidate != null) {
          if (candidate is String) return candidate;
          if (candidate is Map) {
            final nested = candidate['text'] ??
                candidate['content'] ??
                candidate['output'];
            if (nested is String) return nested;
          }
        }
      }
    }
    return response.toString();
  }

  String _cleanJsonResponse(String text) {
    var cleaned = text.trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'^```json\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^```\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1) {
      throw const FormatException('JSON introuvable dans la réponse.');
    }
    return cleaned.substring(firstBrace, lastBrace + 1).trim();
  }

  void _validateConversation(Map<String, dynamic> data) {
    const requiredKeys = [
      'type_reponse',
      'niveau_estime',
      'sujet',
      'intention',
      'segments',
    ];
    for (final key in requiredKeys) {
      if (!data.containsKey(key)) {
        throw FormatException('Champ "$key" manquant dans la réponse IA.');
      }
    }
    final segments = data['segments'];
    if (segments is! List || segments.isEmpty) {
      throw const FormatException('Les segments de réponse sont invalides.');
    }
    for (final seg in segments) {
      if (seg is! Map) {
        throw const FormatException('Un segment est invalide.');
      }
      final langue = seg['langue']?.toString();
      final texte = seg['texte']?.toString().trim() ?? '';
      if ((langue != 'fr' && langue != 'en') || texte.isEmpty) {
        throw const FormatException('Segment mal formé (langue/texte).');
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('FormatException')) {
      return 'Prof IA n’a pas respecté le format attendu. Réessaie.';
    }
    if (message.contains('Failed host lookup') ||
        message.contains('SocketException') ||
        message.contains('ClientException')) {
      return 'Connexion impossible. Vérifie Internet puis réessaie.';
    }
    if (message.contains('429')) {
      return 'Prof IA reçoit trop de demandes. Réessaie dans un instant.';
    }
    return 'Impossible d’obtenir une réponse pour le moment.';
  }

  // =========================================================================
  // AUDIO (TTS — SEULE LA LANGUE CIBLE EST VOCALISÉE)
  // =========================================================================
  //
  // Règle produit : le français reste du texte à l'écran (explication),
  // il n'est jamais lu automatiquement. Seuls les segments "en" et la
  // question de relance ("en") déclenchent une lecture audio.

  Future<void> _playMessageAudio(
      Map<String, dynamic> data, String msgKey) async {
    if (_speakingKeys.contains(msgKey)) return;
    if (!mounted) return;
    setState(() => _speakingKeys.add(msgKey));

    try {
      final segments = data['segments'];
      if (segments is List) {
        for (final seg in segments) {
          if (seg is! Map) continue;
          final texte = seg['texte']?.toString().trim() ?? '';
          final langue = seg['langue']?.toString() ?? 'fr';
          if (texte.isEmpty || langue != 'en') continue; // fr = texte only
          await ServicesVocal.speak(text: texte, voice: _voice);
        }
      }
      final question = data['question_suivante'];
      if (question is Map) {
        final texte = question['texte']?.toString().trim() ?? '';
        final langue = question['langue']?.toString() ?? 'en';
        if (texte.isNotEmpty && langue == 'en') {
          await ServicesVocal.speak(text: texte, voice: _voice);
        }
        // Le champ optionnel "clarification_fr" n'est JAMAIS vocalisé,
        // uniquement affiché en texte (voir _buildQuestionChip).
      }
    } catch (_) {
      // audio optionnel, on ignore silencieusement
    } finally {
      if (!mounted) return;
      setState(() => _speakingKeys.remove(msgKey));
    }
  }

  // =========================================================================
  // SCROLL / UI HELPERS
  // =========================================================================

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: _blue900,
          content: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      );
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: _messages.length + (_isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _messages.length) {
                          return _buildTypingIndicator();
                        }
                        final message = _messages[index];
                        if (message.role == 'user') {
                          return _buildUserBubble(message);
                        }
                        return _buildIaBubble(message, 'ia_$index');
                      },
                    ),
            ),
            if (_errorMessage != null) _buildErrorBanner(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TOP BAR
  // =========================================================================

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _blue900.withOpacity(.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _iconButton(
              Icons.arrow_back_rounded, () => Navigator.maybePop(context)),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_blue900, _blue600]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prof IA • Conversation',
                  style: TextStyle(
                      color: _blue900,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900),
                ),
                Text(
                  'Niveau $_niveauEstime',
                  style: const TextStyle(color: _secondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          _iconButton(Icons.record_voice_over_rounded, _showVoiceSelector),
          const SizedBox(width: 6),
          _iconButton(Icons.refresh_rounded, _resetConversation),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: _blue600.withOpacity(.08),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 19, color: _blue700),
        ),
      ),
    );
  }

  // =========================================================================
  // ÉTAT VIDE / SUJETS DE DÉMARRAGE
  // =========================================================================

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  _blue600.withOpacity(.13),
                  _cyan.withOpacity(.10)
                ]),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.forum_rounded, color: _blue600, size: 34),
            ),
            const SizedBox(height: 18),
            const Text(
              'Discute avec Prof IA',
              style: TextStyle(
                  color: _text, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            const Text(
              'Écris ou parle au micro. Prof IA s’adapte à ton niveau '
              'et avance avec toi, en français et en anglais.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _secondary, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children:
                  _starterTopics.map((topic) => _starterChip(topic)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _starterChip(String topic) {
    return Material(
      color: _blue600.withOpacity(.07),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: () => _sendMessage(topic),
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Text(
            topic,
            style: const TextStyle(
                color: _blue700, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // BULLE UTILISATEUR
  // =========================================================================

  Widget _buildUserBubble(_ChatMessage message) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 60),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_blue700, _blue600]),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          ),
        ),
        child: Text(
          message.text ?? '',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // =========================================================================
  // BULLE IA (SEGMENTS STYLÉS + AUDIO)
  // =========================================================================

  Widget _buildIaBubble(_ChatMessage message, String msgKey) {
    final data = message.data;
    if (data == null) return const SizedBox.shrink();

    final isRefus = data['type_reponse']?.toString() == 'refus';
    final segments = (data['segments'] is List)
        ? List<Map>.from(data['segments'])
        : <Map>[];
    final question = data['question_suivante'];
    final isSpeaking = _speakingKeys.contains(msgKey);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 40),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              isRefus ? Border.all(color: _blue600.withOpacity(.18)) : null,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(
              color: _blue900.withOpacity(.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRefus
                      ? Icons.info_outline_rounded
                      : Icons.auto_awesome_rounded,
                  size: 15,
                  color: isRefus ? _blue600 : _blue700,
                ),
                const SizedBox(width: 6),
                Text(
                  isRefus ? 'Message de Prof IA' : 'Prof IA',
                  style: const TextStyle(
                      color: _secondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                _replayButton(msgKey, data, isSpeaking),
              ],
            ),
            const SizedBox(height: 8),
            ...segments.map((seg) => _buildSegmentText(seg)),
            if (question is Map) ...[
              const SizedBox(height: 10),
              _buildQuestionChip(question),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentText(Map seg) {
    final texte = seg['texte']?.toString() ?? '';
    if (texte.trim().isEmpty) return const SizedBox.shrink();
    final style = seg['style']?.toString() ?? 'normal';
    final couleur = seg['couleur']?.toString() ?? 'noir';
    final langue = seg['langue']?.toString() ?? 'fr';

    final color = couleur == 'rouge' ? _red : _text;
    final weight = (style == 'bold' || style == 'key')
        ? FontWeight.w800
        : FontWeight.w500;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (langue == 'en')
            Container(
              margin: const EdgeInsets.only(top: 3, right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _blue600.withOpacity(.10),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'EN',
                style: TextStyle(
                    color: _blue700, fontSize: 8, fontWeight: FontWeight.w900),
              ),
            ),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                color: color,
                fontSize: 14.5,
                height: 1.4,
                fontWeight: weight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionChip(Map question) {
    final texte = question['texte']?.toString() ?? '';
    if (texte.trim().isEmpty) return const SizedBox.shrink();
    final clarification =
        question['clarification_fr']?.toString().trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _blue600.withOpacity(.06),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline_rounded, color: _blue600, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texte,
                  style: const TextStyle(
                      color: _blue800,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                if (clarification.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '($clarification)',
                    style: const TextStyle(
                        color: _secondary,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replayButton(
      String msgKey, Map<String, dynamic> data, bool isSpeaking) {
    return Material(
      color: _blue600.withOpacity(.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: isSpeaking ? null : () => _playMessageAudio(data, msgKey),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 32,
          height: 32,
          child: isSpeaking
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_blue600),
                  ),
                )
              : const Icon(Icons.volume_up_rounded, size: 16, color: _blue600),
        ),
      ),
    );
  }

  // =========================================================================
  // INDICATEUR "PROF IA ÉCRIT..."
  // =========================================================================

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) {
            final value = 0.5 + (_pulseController.value * 0.5);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(opacity: value, child: _dot()),
                const SizedBox(width: 4),
                Opacity(opacity: 1 - value, child: _dot()),
                const SizedBox(width: 4),
                Opacity(opacity: value, child: _dot()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dot() => Container(
        width: 7,
        height: 7,
        decoration:
            const BoxDecoration(color: _blue600, shape: BoxShape.circle),
      );

  // =========================================================================
  // BANNIÈRE D'ERREUR
  // =========================================================================

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: _red.withOpacity(.08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(
                  color: _red, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _errorMessage = null),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BARRE DE SAISIE (TEXTE + MICRO)
  // =========================================================================

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _blue900.withOpacity(.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Material(
              color: _isListening
                  ? _red.withOpacity(.12)
                  : _blue600.withOpacity(.09),
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                onTap: _toggleListening,
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _isListening ? _red : _blue600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _inputController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 14.5, color: _text),
                  decoration: InputDecoration(
                    hintText: _isListening
                        ? 'Je t’écoute...'
                        : 'Écris en français ou en anglais...',
                    hintStyle: const TextStyle(
                        color: Color(0xFF9AA7B7), fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Material(
              color: _blue700,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                onTap: _isSending ? null : () => _sendMessage(),
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SÉLECTEUR DE VOIX
  // =========================================================================

  void _showVoiceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Voix du professeur',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _text)),
              const SizedBox(height: 14),
              _voiceOption('Alex', Icons.male_rounded),
              const SizedBox(height: 8),
              _voiceOption('Emma', Icons.female_rounded),
            ],
          ),
        );
      },
    );
  }

  Widget _voiceOption(String name, IconData icon) {
    final selected = _voice == name;
    return Material(
      color: selected ? _blue600.withOpacity(.08) : _background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () async {
          Navigator.pop(context);
          await _setVoice(name);
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: selected ? _blue600 : _secondary),
              const SizedBox(width: 10),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: _blue600),
            ],
          ),
        ),
      ),
    );
  }
}