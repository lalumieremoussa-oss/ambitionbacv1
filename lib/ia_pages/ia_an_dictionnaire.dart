// 📁 lib/ia_pages/ia_an_dictionnaire.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ia_services.dart';
import 'servicesvocal.dart';
import '../login/inscription_view.dart';

class IaAnDictionnairePage extends StatefulWidget {
  final String? matiereTitre;

  const IaAnDictionnairePage({
    super.key,
    this.matiereTitre,
  });

  @override
  State<IaAnDictionnairePage> createState() => _IaAnDictionnairePageState();
}

class _IaAnDictionnairePageState extends State<IaAnDictionnairePage>
    with SingleTickerProviderStateMixin {
  // =========================================================================
  // CONSTANTES
  // =========================================================================

  static const String _historyBoxName = 'iaHistoryBox';
  static const String _historyType = 'dictionnaire_an';

  static const String _voiceKey = 'prof_ia_anglais_voice';
  static const String _defaultVoice = 'Alex';
  static const String _level = 'Débutant';

  // ID du prompt dans Supabase (comme HI1, FR1, etc.)
  static const String _promptKey = 'ANG1';

  // Palette bleue
  static const Color _blue900 = Color(0xFF061A40);
  static const Color _blue800 = Color(0xFF0B2D63);
  static const Color _blue700 = Color(0xFF104F9E);
  static const Color _blue600 = Color(0xFF1677D2);
  static const Color _blue500 = Color(0xFF2495F5);
  static const Color _cyan = Color(0xFF4FD9FF);

  static const Color _background = Color(0xFFF5F9FF);
  static const Color _text = Color(0xFF10213A);
  static const Color _secondary = Color(0xFF68778C);
  static const Color _red = Color(0xFFD94747);
  static const Color _gold = Color(0xFFFFB020);

  // =========================================================================
  // CONTROLLERS
  // =========================================================================

  final TextEditingController _wordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;

  // =========================================================================
  // ÉTAT
  // =========================================================================

  bool _isLoading = false;
  String? _errorMessage;
  String? _refusMessage;

  String _voice = _defaultVoice;

  Map<String, dynamic>? _dictionary;
  List<Map<String, dynamic>> _history = [];

  final Set<String> _speakingItems = <String>{};

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _animationController.repeat(reverse: true);

    _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([
      _loadVoice(),
      _loadHistory(),
    ]);
  }

  @override
  void dispose() {
    _wordController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // =========================================================================
  // VOIX & HISTORIQUE
  // =========================================================================

  Future<void> _loadVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVoice = prefs.getString(_voiceKey) ?? _defaultVoice;
      if (!mounted) return;
      setState(() {
        _voice = savedVoice == 'Emma' ? 'Emma' : 'Alex';
      });
    } catch (_) {}
  }

  Future<void> _setVoice(String voice) async {
    final selected = voice == 'Emma' ? 'Emma' : 'Alex';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_voiceKey, selected);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _voice = selected;
    });
    _showMessage(
      'Voix $selected sélectionnée',
      icon: Icons.record_voice_over_rounded,
    );
  }

  Future<void> _loadHistory() async {
    try {
      if (!Hive.isBoxOpen(_historyBoxName)) {
        await Hive.openBox(_historyBoxName);
      }
      final box = Hive.box(_historyBoxName);
      final raw = box.values
          .whereType<Map>()
          .where((item) => item['type']?.toString() == _historyType)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      raw.sort((a, b) {
        final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      if (!mounted) return;
      setState(() {
        _history = raw.take(30).toList();
      });
    } catch (_) {}
  }

  // =========================================================================
  // GESTION DES APPELS (quota 10)
  // =========================================================================
  //
  // IMPORTANT : l'incrément de `iaacces` est géré UNIQUEMENT côté Edge function.
  // Le client Flutter se contente de LIRE cette valeur pour afficher/contrôler
  // la limite d'essai. Il ne doit jamais la modifier lui-même, sinon le
  // compteur serait incrémenté deux fois (une fois par l'Edge, une fois ici).

  Future<String?> _getUserMatricule() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('matricule');
  }

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
      debugPrint('Erreur lors de la vérification des appels : $e');
      return -1;
    }
  }

  // ⚠️ Méthode supprimée : _incrementUsage()
  // Elle est désormais inutile car l'incrément est fait par l'Edge function.
  // Si un jour vous avez besoin de réactiver l'incrémentation côté client,
  // décommentez la méthode ci-dessous MAIS désactivez-la côté Edge pour
  // éviter le double comptage.
  //
  // Future<void> _incrementUsage() async {
  //   final matricule = await _getUserMatricule();
  //   if (matricule == null || matricule.isEmpty) return;
  //
  //   try {
  //     final current = await Supabase.instance.client
  //         .from('utilisateurs_premium')
  //         .select('iaacces')
  //         .eq('matricule', matricule)
  //         .maybeSingle();
  //     if (current != null) {
  //       final int old = current['iaacces'] as int? ?? 0;
  //       await Supabase.instance.client
  //           .from('utilisateurs_premium')
  //           .update({'iaacces': old + 1}).eq('matricule', matricule);
  //     }
  //   } catch (e) {
  //     debugPrint('Erreur lors de l\'incrémentation du compteur : $e');
  //   }
  // }

  // =========================================================================
  // DIALOGUE DE LIMITE ATTEINTE
  // =========================================================================

  Future<void> _showLimitDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: _blue600.withOpacity(.20),
                  blurRadius: 35,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 25, 24, 25),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_blue900, _blue700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(.30),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'Limite d’essai atteinte',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '10 requêtes déjà utilisées',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.88),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 23, 24, 25),
                    child: Column(
                      children: [
                        const Text(
                          'Vous avez atteint la limite de 10 requêtes pour la version d’essai.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _text,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Prof IA vous a offert 10 recherches de dictionnaire anglais. '
                          'Passez à Premium pour un accès illimité et des fonctionnalités supplémentaires.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: _secondary,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _premiumFeature(
                          Icons.auto_awesome_rounded,
                          'Recherches illimitées',
                        ),
                        _premiumFeature(
                          Icons.menu_book_rounded,
                          'Toutes les matières',
                        ),
                        _premiumFeature(
                          Icons.support_agent_rounded,
                          'Priorité et support',
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 53,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const InscriptionView(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _blue700,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            child: const Text(
                              'Découvrir Premium',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Plus tard',
                            style: TextStyle(
                              color: _secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _premiumFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: _blue600.withOpacity(.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: _blue800, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: _blue600, size: 19),
        ],
      ),
    );
  }

  // =========================================================================
  // RECHERCHE (avec quota et promptKey)
  // =========================================================================

  Future<void> _searchWord() async {
    FocusScope.of(context).unfocus();

    final word = _wordController.text.trim();

    if (word.isEmpty) {
      _showMessage(
        'Écris un mot anglais ou français.',
        icon: Icons.edit_rounded,
      );
      return;
    }

    // Vérification des appels restants
    final remaining = await _getRemainingCalls();
    if (remaining == -1) {
      _showMessage(
        'Impossible de vérifier votre statut. Vérifiez votre connexion.',
        icon: Icons.error_outline,
      );
      return;
    }
    if (remaining <= 0) {
      await _showLimitDialog();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _refusMessage = null;
      _dictionary = null;
    });

    try {
      // Appel à IaService avec la clé du prompt (comme pour les autres matières)
      final response = await IaService().chatCompletion(
        promptKey: _promptKey,
        userPrompt: word,
        temperature: 0.2,
        maxTokens: 4000,
      );

      final rawText = _extractResponseText(response);

      if (rawText.trim().isEmpty) {
        throw Exception('Le professeur IA n’a retourné aucune réponse.');
      }

      final cleaned = _cleanJsonResponse(rawText);
      final decoded = jsonDecode(cleaned);

      if (decoded is! Map) {
        throw Exception('La réponse du professeur n’est pas un objet JSON.');
      }

      final data = Map<String, dynamic>.from(decoded);

      // Vérification d'un éventuel refus
      if (data.containsKey('type_reponse') && data['type_reponse'] == 'refus') {
        final message = data['message']?.toString() ??
            'Prof IA ne peut pas traiter cette demande.';
        setState(() {
          _refusMessage = message;
          _isLoading = false;
        });
        return;
      }

      _validateDictionary(data);

      await _saveHistory(
        searchedWord: word,
        result: data,
      );

      // ⚠️ NE PLUS incrémenter ici : c'est l'Edge function qui gère le compteur.
      // await _incrementUsage();   <-- SUPPRIMÉ

      if (!mounted) return;

      setState(() {
        _dictionary = data;
        _isLoading = false;
      });

      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _scrollToResult();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  // =========================================================================
  // EXTRACTION & NETTOYAGE JSON
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
    cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    return cleaned.trim();
  }

  // =========================================================================
  // VALIDATION
  // =========================================================================

  void _validateDictionary(Map<String, dynamic> data) {
    const requiredKeys = [
      'mot',
      'langue',
      'traduction_principale',
      'prononciation_ipa',
      'sens',
      'exemples',
      'verbe',
    ];
    for (final key in requiredKeys) {
      if (!data.containsKey(key)) {
        throw FormatException('Champ "$key" manquant.');
      }
    }

    final examples = data['exemples'];
    if (examples is! List) {
      throw const FormatException('Les exemples sont invalides.');
    }
    if (examples.length != 10) {
      throw FormatException(
        'Le professeur doit fournir exactement 10 exemples. Reçu : ${examples.length}.',
      );
    }
    for (final example in examples) {
      if (example is! Map)
        throw const FormatException('Un exemple est invalide.');
      if (_textValue(example['phrase']).isEmpty ||
          _textValue(example['traduction']).isEmpty ||
          _textValue(example['contexte']).isEmpty) {
        throw const FormatException(
            'Un exemple ne contient pas tous ses éléments.');
      }
    }

    final meanings = data['sens'];
    if (meanings is! List) {
      throw const FormatException('Les sens sont invalides.');
    }

    final verb = data['verbe'];
    if (verb is! Map) {
      throw const FormatException('Les informations du verbe sont invalides.');
    }
    final isVerb = verb['est_verbe'] == true;
    if (isVerb) {
      final conjugation = verb['conjugaison'];
      if (conjugation is! List || conjugation.isEmpty) {
        throw const FormatException('La conjugaison du verbe est absente.');
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('FormatException')) {
      return 'La réponse du professeur n’a pas respecté le format attendu. Essaie à nouveau.';
    }
    if (message.contains('Failed host lookup') ||
        message.contains('SocketException') ||
        message.contains('ClientException')) {
      return 'Connexion impossible. Vérifie Internet puis réessaie.';
    }
    if (message.contains('401') || message.contains('403')) {
      return 'Le service IA n’est pas correctement configuré.';
    }
    if (message.contains('429')) {
      return 'Le professeur reçoit trop de demandes. Réessaie dans quelques instants.';
    }
    return 'Impossible de rechercher ce mot pour le moment.';
  }

  // =========================================================================
  // HISTORIQUE
  // =========================================================================

  Future<void> _saveHistory({
    required String searchedWord,
    required Map<String, dynamic> result,
  }) async {
    try {
      if (!Hive.isBoxOpen(_historyBoxName)) {
        await Hive.openBox(_historyBoxName);
      }
      final box = Hive.box(_historyBoxName);
      final item = {
        'type': _historyType,
        'date': DateTime.now().toIso8601String(),
        'word': searchedWord,
        'result': result,
      };
      await box.add(item);
      await _loadHistory();
    } catch (_) {}
  }

  void _openHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _HistorySheet(
          history: _history,
          onSelect: (item) {
            Navigator.pop(context);
            final word = item['word']?.toString() ?? '';
            final result = item['result'];
            if (result is Map) {
              setState(() {
                _wordController.text = word;
                _dictionary = Map<String, dynamic>.from(result);
                _errorMessage = null;
                _refusMessage = null;
              });
              Future.delayed(
                const Duration(milliseconds: 150),
                _scrollToResult,
              );
            }
          },
        );
      },
    );
  }

  // =========================================================================
  // AUDIO
  // =========================================================================

  Future<void> _speak(String text, {String? key}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    final audioKey = key ?? cleanText;
    if (_speakingItems.contains(audioKey)) return;

    setState(() {
      _speakingItems.add(audioKey);
    });

    try {
      await ServicesVocal.speak(
        text: cleanText,
        voice: _voice,
      );
    } catch (_) {
      // audio optionnel
    } finally {
      if (!mounted) return;
      setState(() {
        _speakingItems.remove(audioKey);
      });
    }
  }

  // =========================================================================
  // NAVIGATION
  // =========================================================================

  void _scrollToResult() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      410,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  String _textValue(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  bool _isVerb() {
    final data = _dictionary;
    if (data == null) return false;
    final verb = data['verbe'];
    if (verb is! Map) return false;
    return verb['est_verbe'] == true;
  }

  List<Map<String, dynamic>> _meanings() {
    final raw = _dictionary?['sens'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _examples() {
    final raw = _dictionary?['exemples'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _conjugations() {
    final raw = _dictionary?['verbe'];
    if (raw is! Map) return [];
    final conjugation = raw['conjugaison'];
    if (conjugation is! List) return [];
    return conjugation
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _showMessage(String message,
      {IconData icon = Icons.info_outline_rounded}) {
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
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
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
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(),
                        const SizedBox(height: 18),
                        _buildSearchBox(),
                        if (_isLoading) ...[
                          const SizedBox(height: 24),
                          _buildLoading(),
                        ],
                        if (_errorMessage != null && !_isLoading) ...[
                          const SizedBox(height: 18),
                          _buildError(),
                        ],
                        if (_refusMessage != null && !_isLoading) ...[
                          const SizedBox(height: 18),
                          _buildRefusMessage(),
                        ],
                        if (_dictionary != null && !_isLoading) ...[
                          const SizedBox(height: 26),
                          _buildDictionaryResult(),
                        ],
                        if (_dictionary == null &&
                            !_isLoading &&
                            _errorMessage == null &&
                            _refusMessage == null) ...[
                          const SizedBox(height: 25),
                          _buildEmptyState(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // COMPOSANTS UI
  // =========================================================================

  Widget _buildBackground() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -130,
            right: -100,
            child: _glowCircle(280, _blue500.withOpacity(.12)),
          ),
          Positioned(
            top: 280,
            left: -180,
            child: _glowCircle(330, _cyan.withOpacity(.08)),
          ),
          Positioned(
            bottom: -160,
            right: -100,
            child: _glowCircle(360, _blue700.withOpacity(.07)),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          _buildTopIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'DICTIONNAIRE',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                        color: _blue900,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _blue600,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Text(
                        'EN',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Prof IA • anglais',
                  style: TextStyle(
                      color: _secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          _buildLevelBadge(),
          const SizedBox(width: 7),
          _buildTopIconButton(
            icon: Icons.record_voice_over_rounded,
            onTap: _showVoiceSelector,
          ),
          const SizedBox(width: 5),
          _buildTopIconButton(
            icon: Icons.history_rounded,
            onTap: _openHistory,
          ),
        ],
      ),
    );
  }

  Widget _buildTopIconButton(
      {required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _blue700.withOpacity(.08)),
            boxShadow: [
              BoxShadow(
                color: _blue900.withOpacity(.05),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, size: 21, color: _blue800),
        ),
      ),
    );
  }

  Widget _buildLevelBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_blue900, _blue700]),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_rounded, color: Colors.white, size: 14),
          SizedBox(width: 5),
          Text(
            'DÉBUTANT',
            style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .6),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_blue900, _blue800, _blue600],
        ),
        boxShadow: [
          BoxShadow(
            color: _blue800.withOpacity(.22),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: Colors.white.withOpacity(.08), width: 25),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -50,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan.withOpacity(.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(.12)),
                    ),
                    child: const Icon(Icons.translate_rounded,
                        color: Colors.white, size: 25),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Text(
                      'Ton laboratoire\n'
                      'de vocabulaire anglais',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Un mot suffit. Prof IA t’explique son sens, '
                'sa prononciation et son utilisation.',
                style: TextStyle(
                  color: Colors.white.withOpacity(.78),
                  fontSize: 13.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 17),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroMiniChip(Icons.language_rounded, 'FR ↔ EN'),
                  _heroMiniChip(Icons.graphic_eq_rounded, 'IPA'),
                  _heroMiniChip(Icons.format_quote_rounded, '10 exemples'),
                  _heroMiniChip(Icons.volume_up_rounded, 'Audio'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMiniChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _cyan),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withOpacity(.86),
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _blue600.withOpacity(.09)),
        boxShadow: [
          BoxShadow(
            color: _blue900.withOpacity(.07),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 11),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _blue600.withOpacity(.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.search_rounded, color: _blue600, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _wordController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchWord(),
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              decoration: const InputDecoration(
                hintText: 'Écris un mot : apple, school, courir...',
                hintStyle: TextStyle(
                  color: Color(0xFF9AA7B7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          Material(
            color: _blue700,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _isLoading ? null : _searchWord,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 50,
                height: 50,
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 23),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _blue600.withOpacity(.08)),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (_, child) {
              final value = 0.94 + (_animationController.value * 0.06);
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [_blue900, _blue500]),
                boxShadow: [
                  BoxShadow(color: _blue500.withOpacity(.25), blurRadius: 25),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 29),
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'Prof IA prépare ton mot...',
            style: TextStyle(
                color: _text, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 7),
          const Text(
            'Recherche du sens • prononciation • exemples',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: const LinearProgressIndicator(
              minHeight: 5,
              backgroundColor: Color(0xFFEAF1FA),
              valueColor: AlwaysStoppedAnimation(_blue500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: _red.withOpacity(.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: _red.withOpacity(.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.error_outline_rounded, color: _red),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Le dictionnaire a rencontré un problème',
                  style: TextStyle(
                      color: _text, fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 5),
                Text(
                  _errorMessage ?? '',
                  style: const TextStyle(
                      color: _secondary, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 11),
                TextButton.icon(
                  onPressed: _searchWord,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Réessayer'),
                  style: TextButton.styleFrom(
                    foregroundColor: _blue700,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // CARTE DE REFUS
  // =========================================================================

  Widget _buildRefusMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: _blue600.withOpacity(.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: _blue600.withOpacity(.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.info_outline_rounded, color: _blue600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Message de Prof IA',
                  style: TextStyle(
                      color: _text, fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 5),
                Text(
                  _refusMessage ?? '',
                  style: const TextStyle(
                      color: _secondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: _blue600.withOpacity(.07)),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [_blue600.withOpacity(.12), _cyan.withOpacity(.10)]),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.menu_book_rounded, color: _blue600, size: 34),
          ),
          const SizedBox(height: 17),
          const Text(
            'Prêt pour ton prochain mot ?',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _text, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 7),
          const Text(
            'Tape un mot en français ou en anglais '
            'et découvre comment il fonctionne.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondary, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 17),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _suggestionChip('beautiful'),
              _suggestionChip('school'),
              _suggestionChip('run'),
              _suggestionChip('apprendre'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String word) {
    return Material(
      color: _blue600.withOpacity(.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          _wordController.text = word;
          _searchWord();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Text(
            word,
            style: const TextStyle(
                color: _blue700, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // DICTIONNAIRE
  // =========================================================================

  Widget _buildDictionaryResult() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWordHero(),
        const SizedBox(height: 18),
        _buildSectionTitle(
          eyebrow: 'COMPRENDRE',
          title: 'Les différents sens',
          icon: Icons.lightbulb_rounded,
        ),
        const SizedBox(height: 10),
        _buildMeanings(),
        const SizedBox(height: 23),
        _buildSectionTitle(
          eyebrow: 'UTILISER',
          title: '10 exemples',
          icon: Icons.format_quote_rounded,
        ),
        const SizedBox(height: 10),
        _buildExamples(),
        if (_isVerb()) ...[
          const SizedBox(height: 24),
          _buildSectionTitle(
            eyebrow: 'MAÎTRISER',
            title: 'Conjugaison',
            icon: Icons.timeline_rounded,
          ),
          const SizedBox(height: 10),
          _buildConjugation(),
        ],
      ],
    );
  }

  Widget _buildWordHero() {
    final word = _textValue(_dictionary?['mot']);
    final language = _textValue(_dictionary?['langue']);
    final translation = _textValue(_dictionary?['traduction_principale']);
    final ipa = _textValue(_dictionary?['prononciation_ipa']);
    final key = 'word_$word';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: _blue500.withOpacity(.13)),
        boxShadow: [
          BoxShadow(
            color: _blue900.withOpacity(.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _blue600.withOpacity(.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  language.isEmpty ? 'LANGUE' : language.toUpperCase(),
                  style: const TextStyle(
                      color: _blue700,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7),
                ),
              ),
              const Spacer(),
              _audioButton(keyValue: key, text: word, compact: false),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  word,
                  style: const TextStyle(
                    color: _blue900,
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ipa.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: _blue900,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                ipa,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_blue600.withOpacity(.08), _cyan.withOpacity(.06)],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.swap_horiz_rounded, color: _blue600, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TRADUCTION PRINCIPALE',
                        style: TextStyle(
                          color: _secondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        translation,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _infoPill(Icons.school_rounded, 'Niveau $_level'),
              const SizedBox(width: 7),
              _infoPill(Icons.record_voice_over_rounded, _voice),
              if (_isVerb()) ...[
                const SizedBox(width: 7),
                _infoPill(Icons.bolt_rounded, 'Verbe'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String text) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _blue600),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _secondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle({
    required String eyebrow,
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _blue600.withOpacity(.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _blue600, size: 19),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                  color: _blue600,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 1),
            Text(
              title,
              style: const TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMeanings() {
    final meanings = _meanings();
    if (meanings.isEmpty) {
      return _emptyMiniCard('Aucun sens détaillé disponible.');
    }
    return Column(
      children: List.generate(
        meanings.length,
        (index) {
          final item = meanings[index];
          final meaning = _textValue(item['sens']);
          final context = _textValue(item['contexte']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child:
                _meaningCard(index: index, meaning: meaning, context: context),
          );
        },
      ),
    );
  }

  Widget _meaningCard({
    required int index,
    required String meaning,
    required String context,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _blue600.withOpacity(.07)),
        boxShadow: [
          BoxShadow(
            color: _blue900.withOpacity(.035),
            blurRadius: 17,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_blue900, _blue600]),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meaning,
                  style: const TextStyle(
                      color: _text,
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w800),
                ),
                if (context.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: _blue600.withOpacity(.055),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.explore_rounded,
                            color: _blue600, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context,
                            style: const TextStyle(
                              color: _secondary,
                              fontSize: 10.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamples() {
    final examples = _examples();
    return Column(
      children: List.generate(
        examples.length,
        (index) {
          final item = examples[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _exampleCard(
              index: index,
              phrase: _textValue(item['phrase']),
              translation: _textValue(item['traduction']),
              context: _textValue(item['contexte']),
            ),
          );
        },
      ),
    );
  }

  Widget _exampleCard({
    required int index,
    required String phrase,
    required String translation,
    required String context,
  }) {
    final audioKey = 'example_${index}_$phrase';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _blue600.withOpacity(.065)),
        boxShadow: [
          BoxShadow(
            color: _blue900.withOpacity(.035),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _blue900,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'EX ${index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5),
                ),
              ),
              const Spacer(),
              _audioButton(keyValue: audioKey, text: phrase, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            phrase,
            style: const TextStyle(
                color: _text,
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.translate_rounded, color: _blue600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    translation,
                    style: const TextStyle(
                        color: _secondary,
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (context.isNotEmpty) ...[
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bookmark_outline_rounded,
                    color: _gold, size: 15),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    context,
                    style: const TextStyle(
                        color: _secondary,
                        fontSize: 10.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _audioButton({
    required String keyValue,
    required String text,
    required bool compact,
  }) {
    final isSpeaking = _speakingItems.contains(keyValue);
    return Material(
      color: _blue600.withOpacity(compact ? .08 : .11),
      borderRadius: BorderRadius.circular(compact ? 12 : 15),
      child: InkWell(
        onTap: isSpeaking ? null : () => unawaited(_speak(text, key: keyValue)),
        borderRadius: BorderRadius.circular(compact ? 12 : 15),
        child: SizedBox(
          width: compact ? 40 : 47,
          height: compact ? 40 : 47,
          child: isSpeaking
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_blue600),
                  ),
                )
              : Icon(
                  Icons.volume_up_rounded,
                  size: compact ? 19 : 22,
                  color: _blue600,
                ),
        ),
      ),
    );
  }

  Widget _buildConjugation() {
    final conjugations = _conjugations();
    if (conjugations.isEmpty) {
      return _emptyMiniCard('Aucune conjugaison disponible.');
    }
    return Column(
      children: List.generate(
        conjugations.length,
        (index) {
          final item = conjugations[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _conjugationCard(
              index: index,
              time: _textValue(item['temps']),
              form: _textValue(item['forme']),
              example: _textValue(item['exemple']),
              translation: _textValue(item['traduction']),
            ),
          );
        },
      ),
    );
  }

  Widget _conjugationCard({
    required int index,
    required String time,
    required String form,
    required String example,
    required String translation,
  }) {
    final audioKey = 'conjugation_${index}_$example';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _blue600.withOpacity(.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: _blue600.withOpacity(.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  time,
                  style: const TextStyle(
                      color: _blue700,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              _audioButton(keyValue: audioKey, text: example, compact: true),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            form,
            style: const TextStyle(
                color: _blue900, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          if (example.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              example,
              style: const TextStyle(
                  color: _text,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w700),
            ),
          ],
          if (translation.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              translation,
              style: const TextStyle(
                  color: _secondary, fontSize: 11.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyMiniCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _secondary, fontSize: 12),
      ),
    );
  }

  // =========================================================================
  // VOICE SELECTOR
  // =========================================================================

  void _showVoiceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE5EF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Voix du professeur',
                style: TextStyle(
                    color: _text, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              const Text(
                'Choisis la voix utilisée pour écouter '
                'les mots et les phrases anglaises.',
                style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 18),
              _voiceChoice(
                  name: 'Alex',
                  subtitle: 'Voix anglaise • Alex',
                  icon: Icons.male_rounded),
              const SizedBox(height: 9),
              _voiceChoice(
                  name: 'Emma',
                  subtitle: 'Voix anglaise • Emma',
                  icon: Icons.female_rounded),
            ],
          ),
        );
      },
    );
  }

  Widget _voiceChoice({
    required String name,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _voice == name;
    return Material(
      color: selected ? _blue600.withOpacity(.08) : _background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () async {
          Navigator.pop(context);
          await _setVoice(name);
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? _blue600 : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: selected ? Colors.white : _blue600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _secondary, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _blue600,
                  size: 23,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// HISTORIQUE
// =============================================================================

class _HistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final void Function(Map<String, dynamic> item) onSelect;

  const _HistorySheet({
    required this.history,
    required this.onSelect,
  });

  static const Color blue900 = Color(0xFF061A40);
  static const Color blue600 = Color(0xFF1677D2);
  static const Color text = Color(0xFF10213A);
  static const Color secondary = Color(0xFF68778C);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * .72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Color(0xFFDDE5EF),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: blue600.withOpacity(.09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.history_rounded, color: blue600),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Historique',
                        style: TextStyle(
                            color: text,
                            fontSize: 19,
                            fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tes dernières recherches',
                        style: TextStyle(color: secondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined,
                            color: secondary, size: 40),
                        SizedBox(height: 10),
                        Text(
                          'Aucune recherche récente',
                          style: TextStyle(
                              color: text, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 25),
                    physics: const BouncingScrollPhysics(),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final item = history[index];
                      final word = item['word']?.toString() ?? '';
                      final result = item['result'];
                      String translation = '';
                      if (result is Map) {
                        translation =
                            result['traduction_principale']?.toString() ?? '';
                      }
                      return Material(
                        color: const Color(0xFFF6F9FD),
                        borderRadius: BorderRadius.circular(17),
                        child: InkWell(
                          onTap: () => onSelect(item),
                          borderRadius: BorderRadius.circular(17),
                          child: Padding(
                            padding: const EdgeInsets.all(13),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [blue900, blue600]),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(Icons.language_rounded,
                                      color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        word,
                                        style: const TextStyle(
                                            color: text,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900),
                                      ),
                                      if (translation.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: Text(
                                            translation,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: secondary,
                                                fontSize: 10.5),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    color: secondary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
