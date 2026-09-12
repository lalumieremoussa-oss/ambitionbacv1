// 📁 lib/ia_pages/ia_fr_dissertation.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ocr_service.dart';
import 'ia_services.dart';
import '../login/inscription_view.dart';

class IaFrDissertationScreen extends StatefulWidget {
  final String matiereTitre;

  const IaFrDissertationScreen({
    super.key,
    required this.matiereTitre,
  });

  @override
  State<IaFrDissertationScreen> createState() => _IaFrDissertationScreenState();
}

class _IaFrDissertationScreenState extends State<IaFrDissertationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _subjectController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;

  Map<String, dynamic>? _result;
  bool _isGenerating = false;
  String? _errorMessage;
  String? _refusMessage;
  bool _isOcrProcessing = false;

  // Clé du prompt stocké dans Supabase (identique à celle utilisée dans la table)
  static const String _promptKey = 'FR1';

  // ==========================================================
  // IDENTITÉ VISUELLE
  // ==========================================================

  static const Color ivoire = Color(0xFFFFF8F0);
  static const Color ivoireDeep = Color(0xFFF8EBDD);

  static const Color orange = Color(0xFFFF7900);
  static const Color orangeDark = Color(0xFFE85F00);

  static const Color vert = Color(0xFF169B62);
  static const Color vertDark = Color(0xFF087A4A);

  static const Color jaune = Color(0xFFFCD116);

  static const Color texte = Color(0xFF202020);
  static const Color texteSecondaire = Color(0xFF707070);

  // ==========================================================
  // HISTORIQUE HIVE
  // ==========================================================

  static const String _historyBoxName = 'iaHistoryBox';
  static const String _historyType = 'dissertation_fr';

  Future<void> _saveHistory(
      String question, Map<String, dynamic> response) async {
    try {
      final box = await Hive.openBox(_historyBoxName);
      final entry = {
        'question': question,
        'response': jsonEncode(response),
        'timestamp': DateTime.now().toIso8601String(),
        'type': _historyType,
      };
      await box.add(entry);
    } catch (e) {
      debugPrint('Erreur sauvegarde historique : $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    try {
      final box = await Hive.openBox(_historyBoxName);
      final all = box.values.map((e) => Map<String, dynamic>.from(e)).toList();
      return all.where((entry) => entry['type'] == _historyType).toList();
    } catch (e) {
      debugPrint('Erreur chargement historique : $e');
      return [];
    }
  }

  void _showHistoryDialog() async {
    final history = await _loadHistory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: ivoire,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(Icons.history, color: orange),
                        SizedBox(width: 8),
                        Text(
                          'Historique des analyses',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: texte,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: history.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Aucune analyse enregistrée pour le moment.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: texteSecondaire,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: history.length,
                            itemBuilder: (_, index) {
                              final entry = history.reversed.toList()[index];
                              final question = entry['question'] ?? '';
                              final timestamp = entry['timestamp'] ?? '';
                              final date = timestamp.isNotEmpty
                                  ? DateTime.parse(timestamp)
                                  : null;
                              final formattedDate = date != null
                                  ? '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
                                  : 'Date inconnue';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: orange.withOpacity(0.1),
                                  child: const Icon(
                                    Icons.question_answer,
                                    color: orange,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  question.length > 60
                                      ? '${question.substring(0, 60)}…'
                                      : question,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: texte,
                                  ),
                                ),
                                subtitle: Text(
                                  formattedDate,
                                  style: const TextStyle(
                                    color: texteSecondaire,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: texteSecondaire,
                                ),
                                onTap: () {
                                  final responseJson = entry['response'];
                                  if (responseJson == null) return;
                                  try {
                                    final decoded = jsonDecode(responseJson)
                                        as Map<String, dynamic>;
                                    Navigator.pop(context);
                                    _restoreFromHistory(decoded, question);
                                  } catch (e) {
                                    _showElegantSnack(
                                      'Erreur lors de l’affichage de l’historique.',
                                      Icons.error_outline,
                                    );
                                  }
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _restoreFromHistory(Map<String, dynamic> decoded, String question) {
    setState(() {
      _subjectController.text = question;
      _subjectController.selection = TextSelection.collapsed(
        offset: _subjectController.text.length,
      );
      _result = decoded;
      _errorMessage = null;
      _refusMessage = null;
      _isGenerating = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 150));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        );
      }
    });

    _showElegantSnack(
      'Analyse restaurée depuis l’historique',
      Icons.history,
    );
  }

  // ==========================================================
  // GESTION DES APPELS (Supabase)
  // ==========================================================
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

  // ==========================================================
  // DIALOGUE DE LIMITE ATTEINTE
  // ==========================================================

  Future<void> _showLimitDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ivoire,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: orange.withOpacity(.20),
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
                        colors: [orange, orangeDark],
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
                            color: texte,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Prof IA vous a offert 10 analyses de sujets de dissertation française. '
                          'Passez à Premium pour un accès illimité et des fonctionnalités supplémentaires.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: texteSecondaire,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _premiumFeature(
                          Icons.auto_awesome_rounded,
                          'Analyses illimitées',
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
                              backgroundColor: orange,
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
                              color: texteSecondaire,
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
              color: vert.withOpacity(.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: vertDark, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: texte,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: vert, size: 19),
        ],
      ),
    );
  }

  // ==========================================================
  // OCR - Utilisation du service
  // ==========================================================

  Future<void> _pickImageForOcr() async {
    if (_isOcrProcessing) return;

    setState(() => _isOcrProcessing = true);

    try {
      final extracted = await OcrService.showImageSourceAndExtract(context);

      if (extracted != null && extracted.isNotEmpty) {
        setState(() {
          final current = _subjectController.text.trim();
          _subjectController.text =
              current.isEmpty ? extracted : '$current\n$extracted';
          _subjectController.selection = TextSelection.collapsed(
            offset: _subjectController.text.length,
          );
        });
        _focusNode.requestFocus();
        _showElegantSnack(
          'Texte importé depuis l’image.',
          Icons.check_circle_outline_rounded,
        );
      } else if (extracted == null) {
        // Annulé par l'utilisateur
      } else {
        _showElegantSnack(
          'Aucun texte lisible n’a été trouvé sur cette image.',
          Icons.image_not_supported_outlined,
        );
      }
    } catch (e) {
      _showElegantSnack(
        'Impossible de lire le texte de cette image.',
        Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isOcrProcessing = false);
    }
  }

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ==========================================================
  // ENVOI (avec promptKey)
  // ==========================================================

  Future<void> _submitSubject() async {
    final subject = _subjectController.text.trim();

    if (subject.isEmpty) {
      _showElegantSnack(
        'Écris d’abord ton sujet de dissertation.',
        Icons.edit_note_rounded,
      );
      return;
    }

    if (_isGenerating) return;

    // Vérification des appels restants
    final remaining = await _getRemainingCalls();
    if (remaining == -1) {
      _showElegantSnack(
        'Impossible de vérifier votre statut. Vérifiez votre connexion.',
        Icons.error_outline,
      );
      return;
    }
    if (remaining <= 0) {
      await _showLimitDialog();
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _refusMessage = null;
      _result = null;
    });

    try {
      final response = await IaService().chatCompletion(
        promptKey: _promptKey,
        userPrompt: subject,
        temperature: 0.2,
        maxTokens: 4000,
      );

      if (!mounted) return;

      final cleaned = _cleanJsonResponse(response);
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      // Vérification du refus de l'IA
      if (decoded.containsKey('type_reponse') &&
          decoded['type_reponse'] == 'refus') {
        final message = decoded['message']?.toString() ??
            'Prof IA ne peut pas traiter cette demande.';
        setState(() {
          _refusMessage = message;
          _isGenerating = false;
        });
        return;
      }

      // Validation de la structure JSON (spécifique à la dissertation française)
      final validationError = _validateDissertationJson(decoded);
      if (validationError != null) throw FormatException(validationError);

      await _saveHistory(subject, decoded);

      // ⚠️ NE PLUS incrémenter ici : c'est l'Edge function qui gère le compteur.
      // await _incrementUsage();   <-- SUPPRIMÉ

      setState(() {
        _result = decoded;
        _isGenerating = false;
      });

      await Future.delayed(const Duration(milliseconds: 150));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  // ==========================================================
  // NETTOYAGE JSON
  // ==========================================================

  String _cleanJsonResponse(String response) {
    String text = response.trim();

    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }

    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }

    text = text.trim();

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');

    if (firstBrace >= 0 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }

    return text.trim();
  }

  // ==========================================================
  // VALIDATION DU JSON (structure spécifique à la dissertation française)
  // ==========================================================

  String? _validateDissertationJson(Map<String, dynamic> json) {
    final requiredTopLevel = [
      'sujet',
      'etude_preliminaire',
      'annonce_des_axes',
      'developpement',
      'conclusion',
      'controle',
    ];

    for (final key in requiredTopLevel) {
      if (!json.containsKey(key)) {
        return 'Structure JSON incomplète : $key manquant.';
      }
    }

    final development = json['developpement'];
    if (development is! Map) {
      return 'Structure du développement invalide.';
    }

    final part1 = development['partie_1'];
    final part2 = development['partie_2'];

    if (part1 is! Map || part2 is! Map) {
      return 'Les deux parties sont obligatoires.';
    }

    final arguments1 = part1['arguments'];
    final arguments2 = part2['arguments'];

    if (arguments1 is! List || arguments1.length != 3) {
      return 'La partie I doit contenir exactement 3 arguments.';
    }

    if (arguments2 is! List || arguments2.length != 3) {
      return 'La partie II doit contenir exactement 3 arguments.';
    }

    final preliminary = json['etude_preliminaire'];
    if (preliminary is! Map) {
      return 'Étude préliminaire invalide.';
    }

    final problematique = preliminary['problematique'];
    if (problematique is! Map) {
      return 'Problématique invalide.';
    }

    if (!problematique.containsKey('question_these') ||
        !problematique.containsKey('question_antithese')) {
      return 'La problématique doit contenir exactement les deux questions demandées.';
    }

    final conclusion = json['conclusion'];
    if (conclusion is! Map) {
      return 'Conclusion invalide.';
    }

    return null;
  }

  // ==========================================================
  // ERREURS
  // ==========================================================

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('format') ||
        message.contains('json') ||
        message.contains('structure')) {
      return 'Prof IA n’a pas reçu une correction dans le format attendu. Réessaie avec ton sujet.';
    }

    if (message.contains('429')) {
      return 'Prof IA reçoit beaucoup de demandes actuellement. Réessaie dans quelques instants.';
    }

    if (message.contains('401')) {
      return 'Le professeur IA rencontre un problème d’autorisation.';
    }

    if (message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('socket')) {
      return 'La connexion avec Prof IA a été interrompue. Vérifie ta connexion puis réessaie.';
    }

    return 'Prof IA n’a pas pu terminer l’analyse. Réessaie dans quelques instants.';
  }

  // ==========================================================
  // SNACKBAR ÉLÉGANT
  // ==========================================================

  void _showElegantSnack(String message, IconData icon) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        backgroundColor: texte,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
        ),
        content: Row(
          children: [
            Icon(icon, color: jaune, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ivoire,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHero()),
                  SliverToBoxAdapter(child: _buildSubjectComposer()),
                  if (_isGenerating)
                    SliverToBoxAdapter(child: _buildThinkingCard()),
                  if (_errorMessage != null)
                    SliverToBoxAdapter(child: _buildProfError()),
                  if (_refusMessage != null)
                    SliverToBoxAdapter(child: _buildRefusMessage()),
                  if (_result != null)
                    SliverToBoxAdapter(child: _buildResult()),
                  const SliverToBoxAdapter(child: SizedBox(height: 50)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CARTE DE REFUS (message de l'IA)
  // ==========================================================

  Widget _buildRefusMessage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1EB),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: orange.withOpacity(.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prof IA',
                        style: TextStyle(
                          color: orangeDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Message pédagogique',
                        style: TextStyle(
                          color: texteSecondaire,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _refusMessage ?? '',
              style: const TextStyle(
                color: texte,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.75),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: vertDark,
                    size: 18,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Prof IA est spécialisé en dissertation française. Envoie un sujet littéraire pour obtenir un plan détaillé.',
                      style: TextStyle(
                        color: texteSecondaire,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // TOP BAR (avec bouton Historique)
  // ==========================================================

  Widget _buildTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: ivoire,
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(.05),
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.black.withOpacity(.05),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: texte,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [orange, orangeDark],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROF IA',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: texte,
                  ),
                ),
                Text(
                  'Dissertation française',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: texteSecondaire,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showHistoryDialog,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: orange.withOpacity(0.15),
                ),
              ),
              child: const Icon(
                Icons.history,
                color: orange,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: vert.withOpacity(.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 15,
                  color: vert,
                ),
                SizedBox(width: 5),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: vertDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HERO
  // ==========================================================

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(23, 24, 23, 23),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8B20), Color(0xFFE95F00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(29),
          boxShadow: [
            BoxShadow(
              color: orange.withOpacity(.20),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -25,
              top: -28,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 32,
              bottom: -55,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'ATELIER DE DISSERTATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Construis ton plan.\nDéfends tes idées.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  'Prof IA analyse ton sujet et transforme ta réflexion en véritable feuille de route.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.90),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _heroBadge(Icons.account_tree_rounded, 'PLAN'),
                    const SizedBox(width: 8),
                    _heroBadge(Icons.menu_book_rounded, 'EXEMPLES'),
                    const SizedBox(width: 8),
                    _heroBadge(Icons.compare_arrows_rounded, 'THÈSE'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: Colors.white.withOpacity(.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPOSITEUR DU SUJET (avec bouton OCR)
  // ==========================================================

  Widget _buildSubjectComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(27),
          border: Border.all(
            color: Colors.black.withOpacity(.055),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.045),
              blurRadius: 20,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 19, 19, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: vert.withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit_document,
                      color: vertDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ton sujet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: texte,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Écris exactement le sujet donné en classe.',
                          style: TextStyle(
                            fontSize: 11,
                            color: texteSecondaire,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                decoration: BoxDecoration(
                  color: ivoire,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: orange.withOpacity(.10),
                  ),
                ),
                child: TextField(
                  controller: _subjectController,
                  focusNode: _focusNode,
                  minLines: 5,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: texte,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Exemple :\n« La littérature doit-elle nécessairement servir au progrès de la société ? »',
                    hintStyle: TextStyle(
                      color: Color(0xFFAAA29A),
                      height: 1.45,
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(17),
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: orange,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Un sujet précis donne une analyse plus précise.',
                      style: TextStyle(
                        color: texteSecondaire,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  GestureDetector(
                    onTap: _isOcrProcessing ? null : _pickImageForOcr,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: vert.withOpacity(.10),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: vert.withOpacity(.15),
                        ),
                      ),
                      child: _isOcrProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(vertDark),
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: vertDark,
                              size: 21,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isOcrProcessing
                          ? 'Lecture du texte de l’image…'
                          : 'Importer une photo du sujet',
                      style: const TextStyle(
                        color: texteSecondaire,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _submitSubject,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [orange, orangeDark],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: orange.withOpacity(.20),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'Analyser',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // PROF IA EN TRAIN DE TRAVAILLER
  // ==========================================================

  Widget _buildThinkingCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 7),
      child: Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: orange.withOpacity(.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [orange, orangeDark],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prof IA travaille...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: texte,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Lecture du sujet • construction des axes • vérification des exemples',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // ERREUR / QUESTION INAPPROPRIÉE
  // ==========================================================

  Widget _buildProfError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1EB),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: orange.withOpacity(.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prof IA',
                        style: TextStyle(
                          color: orangeDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Un petit arrêt pédagogique',
                        style: TextStyle(
                          color: texteSecondaire,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ??
                  'Désolé, je suis là pour t’aider à travailler ta dissertation française.',
              style: const TextStyle(
                color: texte,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.75),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: vertDark,
                    size: 18,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Envoie un sujet de dissertation littéraire française pour commencer.',
                      style: TextStyle(
                        color: texteSecondaire,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // RESULTAT PRINCIPAL
  // ==========================================================

  Widget _buildResult() {
    final result = _result!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultHeader(result),
          const SizedBox(height: 16),
          _buildSubjectResult(result),
          const SizedBox(height: 15),
          _buildPreliminary(result),
          const SizedBox(height: 15),
          _buildAxes(result),
          const SizedBox(height: 15),
          _buildDevelopment(result),
          const SizedBox(height: 15),
          _buildConclusion(result),
        ],
      ),
    );
  }

  // ==========================================================
  // HEADER RESULTAT
  // ==========================================================

  Widget _buildResultHeader(Map<String, dynamic> result) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TA FEUILLE DE ROUTE',
                style: TextStyle(
                  color: orangeDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Plan détaillé',
                style: TextStyle(
                  color: texte,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: vert.withOpacity(.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: vert,
                size: 15,
              ),
              SizedBox(width: 5),
              Text(
                'ANALYSÉ',
                style: TextStyle(
                  color: vertDark,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SUJET
  // ==========================================================

  Widget _buildSubjectResult(Map<String, dynamic> result) {
    return _sectionContainer(
      accent: orange,
      icon: Icons.format_quote_rounded,
      label: 'SUJET',
      child: Text(
        '${result['sujet'] ?? ''}',
        style: const TextStyle(
          color: texte,
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ==========================================================
  // ETUDE PRELIMINAIRE
  // ==========================================================

  Widget _buildPreliminary(Map<String, dynamic> result) {
    final data = Map<String, dynamic>.from(
      result['etude_preliminaire'] ?? {},
    );

    final definitions = (data['definitions'] as List?) ?? [];

    final problematique = Map<String, dynamic>.from(
      data['problematique'] ?? {},
    );

    return _sectionContainer(
      accent: vert,
      icon: Icons.search_rounded,
      label: 'ÉTUDE PRÉLIMINAIRE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniLabel('Mots clés'),
          const SizedBox(height: 9),
          ...definitions.map(
            (item) {
              final d = Map<String, dynamic>.from(
                item as Map,
              );

              return _definitionTile(
                d['mot']?.toString() ?? '',
                d['definition_contextuelle']?.toString() ?? '',
              );
            },
          ),
          const SizedBox(height: 16),
          _miniLabel('Reformulation'),
          const SizedBox(height: 7),
          _textBlock(
            data['reformulation'],
          ),
          const SizedBox(height: 16),
          _miniLabel('Thème'),
          const SizedBox(height: 7),
          _softHighlight(
            data['theme']?.toString() ?? '',
          ),
          const SizedBox(height: 16),
          _miniLabel('Constat'),
          const SizedBox(height: 7),
          _textBlock(
            data['constat'],
          ),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8F5),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: vert.withOpacity(.12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      color: vertDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'PROBLÉMATIQUE',
                      style: TextStyle(
                        color: vertDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                _questionCard(
                  'THÈSE',
                  problematique['question_these']?.toString() ?? '',
                  orange,
                ),
                const SizedBox(height: 9),
                _questionCard(
                  'ANTITHÈSE',
                  problematique['question_antithese']?.toString() ?? '',
                  vert,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // AXES
  // ==========================================================

  Widget _buildAxes(Map<String, dynamic> result) {
    final axes = Map<String, dynamic>.from(
      result['annonce_des_axes'] ?? {},
    );

    final axe1 = Map<String, dynamic>.from(
      axes['axe_1'] ?? {},
    );

    final axe2 = Map<String, dynamic>.from(
      axes['axe_2'] ?? {},
    );

    return _sectionContainer(
      accent: jaune,
      icon: Icons.alt_route_rounded,
      label: 'ANNONCE DES AXES',
      child: Column(
        children: [
          _axisCard(
            number: 'I',
            title: 'THÈSE',
            text: axe1['formulation']?.toString() ?? '',
            color: orange,
          ),
          const SizedBox(height: 11),
          _axisConnector(),
          const SizedBox(height: 11),
          _axisCard(
            number: 'II',
            title: 'ANTITHÈSE',
            text: axe2['formulation']?.toString() ?? '',
            color: vert,
          ),
        ],
      ),
    );
  }

  Widget _axisConnector() {
    return Row(
      children: [
        const SizedBox(width: 22),
        Container(
          width: 2,
          height: 20,
          color: Colors.black.withOpacity(.08),
        ),
        const SizedBox(width: 9),
        const Text(
          'Mais la littérature peut aussi…',
          style: TextStyle(
            color: texteSecondaire,
            fontSize: 10.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // DEVELOPPEMENT
  // ==========================================================

  Widget _buildDevelopment(Map<String, dynamic> result) {
    final development = Map<String, dynamic>.from(
      result['developpement'] ?? {},
    );

    final part1 = Map<String, dynamic>.from(
      development['partie_1'] ?? {},
    );

    final part2 = Map<String, dynamic>.from(
      development['partie_2'] ?? {},
    );

    final transition = Map<String, dynamic>.from(
      development['transition'] ?? {},
    );

    final args1 = (part1['arguments'] as List?) ?? [];

    final args2 = (part2['arguments'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(
            left: 3,
            bottom: 11,
          ),
          child: Text(
            'DÉVELOPPEMENT',
            style: TextStyle(
              color: orangeDark,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _buildPart(
          number: 'I',
          title: part1['titre']?.toString() ?? 'Thèse',
          type: 'THÈSE',
          arguments: args1,
          color: orange,
        ),
        const SizedBox(height: 14),
        _buildTransition(
          transition,
        ),
        const SizedBox(height: 14),
        _buildPart(
          number: 'II',
          title: part2['titre']?.toString() ?? 'Antithèse',
          type: 'ANTITHÈSE',
          arguments: args2,
          color: vert,
        ),
      ],
    );
  }

  // ==========================================================
  // PARTIE
  // ==========================================================

  Widget _buildPart({
    required String number,
    required String title,
    required String type,
    required List arguments,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: color.withOpacity(.13),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 17,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withOpacity(.055),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 47,
                  height: 47,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
                        style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        style: const TextStyle(
                          color: texte,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.09),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${arguments.length} ARGUMENTS',
                    style: TextStyle(
                      color: color,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              children: [
                for (int i = 0; i < arguments.length; i++)
                  _argumentCard(
                    argument: arguments[i],
                    index: i + 1,
                    color: color,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ARGUMENT
  // ==========================================================

  Widget _argumentCard({
    required dynamic argument,
    required int index,
    required Color color,
  }) {
    final data = Map<String, dynamic>.from(
      argument as Map,
    );

    final exemple = Map<String, dynamic>.from(
      data['exemple'] ?? {},
    );

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: Colors.black.withOpacity(.045),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                'ARGUMENT',
                style: TextStyle(
                  color: texteSecondaire,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _miniLabel('IDÉE'),
          const SizedBox(height: 5),
          Text(
            data['idee']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 13),
          _miniLabel('EXPLICATION'),
          const SizedBox(height: 5),
          Text(
            data['explication']?.toString() ?? '',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(.14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      color: color,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'EXEMPLE LITTÉRAIRE',
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  exemple['auteur']?.toString() ?? '',
                  style: const TextStyle(
                    color: texte,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  exemple['oeuvre']?.toString() ?? '',
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  exemple['idee_illustree']?.toString() ?? '',
                  style: const TextStyle(
                    color: texteSecondaire,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TRANSITION
  // ==========================================================

  Widget _buildTransition(
    Map<String, dynamic> transition,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8E8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: jaune.withOpacity(.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: jaune,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.swap_vert_rounded,
              color: texte,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TRANSITION',
                  style: TextStyle(
                    color: texte,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _transitionLine(
                  'Limite de la thèse',
                  transition['limite_de_la_these']?.toString() ?? '',
                ),
                const SizedBox(height: 9),
                _transitionLine(
                  'Vers l’antithèse',
                  transition['orientation_vers_antithese']?.toString() ?? '',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transitionLine(
    String title,
    String text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: texteSecondaire,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          text,
          style: const TextStyle(
            color: texte,
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // CONCLUSION
  // ==========================================================

  Widget _buildConclusion(
    Map<String, dynamic> result,
  ) {
    final conclusion = Map<String, dynamic>.from(
      result['conclusion'] ?? {},
    );

    return _sectionContainer(
      accent: vert,
      icon: Icons.flag_rounded,
      label: 'CONCLUSION — INDICATIONS',
      child: Column(
        children: [
          _conclusionItem(
            icon: Icons.check_circle_outline_rounded,
            title: 'Réponse à la question',
            text: conclusion['reponse_a_la_question']?.toString() ?? '',
            color: vert,
          ),
          const SizedBox(height: 11),
          _conclusionItem(
            icon: Icons.open_in_new_rounded,
            title: 'Ouverture',
            text: conclusion['ouverture']?.toString() ?? '',
            color: orange,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: ivoireDeep,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.school_rounded,
                  color: orangeDark,
                  size: 18,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'À toi maintenant de transformer ce plan en dissertation. Prof IA te donne la direction, mais c’est toi qui construis ta rédaction.',
                    style: TextStyle(
                      color: texteSecondaire,
                      fontSize: 11.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
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

  Widget _conclusionItem({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    color: texte,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPOSANTS UI
  // ==========================================================

  Widget _sectionContainer({
    required Color accent,
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: accent.withOpacity(.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: accent == jaune ? texte : accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          child,
        ],
      ),
    );
  }

  Widget _miniLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: texteSecondaire,
        fontSize: 8.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  Widget _textBlock(dynamic value) {
    return Text(
      value?.toString() ?? '',
      style: const TextStyle(
        color: texte,
        fontSize: 13,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _softHighlight(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ivoireDeep,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: texte,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _definitionTile(
    String word,
    String definition,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 7,
      ),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(13),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$word : ',
              style: const TextStyle(
                color: orangeDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: definition,
              style: const TextStyle(
                color: texteSecondaire,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard(
    String label,
    String question,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 7.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              question,
              style: const TextStyle(
                color: texte,
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _axisCard({
    required String number,
    required String title,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.055),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: color.withOpacity(.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: texte,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
