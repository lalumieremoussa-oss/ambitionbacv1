// 📁 lib/ia_pages/ia_ge_commentaire.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'ocr_service.dart';
import 'ia_services.dart';
import '../login/inscription_view.dart';

class IaGeCommentaireScreen extends StatefulWidget {
  final String matiereTitre;

  const IaGeCommentaireScreen({
    super.key,
    required this.matiereTitre,
  });

  @override
  State<IaGeCommentaireScreen> createState() => _IaGeCommentaireScreenState();
}

class _IaGeCommentaireScreenState extends State<IaGeCommentaireScreen>
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

  // Clé du prompt stocké dans Supabase (GE2 pour le commentaire géographique)
  static const String _promptKey = 'GE2';

  // ==========================================================
  // IDENTITÉ VISUELLE (spécifique à la géographie, inchangée)
  // ==========================================================

  static const Color ivoire = Color(0xFFFFF8F0);

  // Couleur principale (vert)
  static const Color orange = Color(0xFF169B62);
  static const Color orangeDark = Color(0xFF087A4A);

  // Couleur secondaire (orange)
  static const Color vert = Color(0xFFFF7900);
  static const Color vertDark = Color(0xFFE85F00);

  static const Color jaune = Color(0xFFFCD116);
  static const Color texte = Color(0xFF202020);
  static const Color texteSecondaire = Color(0xFF707070);

  // ==========================================================
  // HISTORIQUE HIVE
  // ==========================================================

  static const String _historyBoxName = 'iaHistoryBox';
  static const String _historyType = 'commentaire_ge';

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
                          'Historique des exploitations de texte',
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
                                'Aucune exploitation enregistrée pour le moment.',
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
                                    Icons.public_rounded,
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
                          'Prof IA vous a offert 10 exploitations de textes géographiques. '
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
              color: orange.withOpacity(.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: orangeDark, size: 19),
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
          const Icon(Icons.check_circle_rounded, color: orange, size: 19),
        ],
      ),
    );
  }

  // ==========================================================
  // OCR
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
        'Écris d’abord le texte géographique à exploiter.',
        Icons.edit_document,
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

      // Validation de la structure JSON (spécifique à la géographie)
      final validationError = _validateGeographieJson(decoded);
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
  // VALIDATION DU JSON GÉOGRAPHIQUE (inchangée)
  // ==========================================================

  String? _validateGeographieJson(Map<String, dynamic> json) {
    final requiredTopLevel = [
      'document',
      'decryptage',
      'questions',
      'cas_avis_auteur',
      'controle',
    ];

    for (final key in requiredTopLevel) {
      if (!json.containsKey(key)) {
        return 'Structure JSON incomplète : $key manquant.';
      }
    }

    final doc = json['document'] as Map<String, dynamic>?;
    if (doc == null) return 'Le champ "document" doit être un objet.';
    final requiredDoc = [
      'titre',
      'nature',
      'origine',
      'date',
      'auteur',
      'espace_etudie',
      'contexte_geographique',
      'theme',
      'idee_principale',
      'intention'
    ];
    for (final key in requiredDoc) {
      if (!doc.containsKey(key)) {
        return 'Le champ "document.$key" est manquant.';
      }
    }

    final dec = json['decryptage'] as Map<String, dynamic>?;
    if (dec == null) return 'Le champ "decryptage" doit être un objet.';
    final requiredDec = [
      'termes_cles',
      'localisations',
      'phenomenes_geographiques',
      'facteurs',
      'consequences',
      'limites_du_document'
    ];
    for (final key in requiredDec) {
      if (!dec.containsKey(key)) {
        return 'Le champ "decryptage.$key" est manquant.';
      }
    }

    final questions = json['questions'] as List?;
    if (questions == null || questions.isEmpty) {
      return 'Le champ "questions" doit être une liste non vide.';
    }
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i] as Map<String, dynamic>?;
      if (q == null) return 'La question $i est invalide.';
      final requiredQ = [
        'numero',
        'question',
        'type',
        'reponse',
        'justification'
      ];
      for (final key in requiredQ) {
        if (!q.containsKey(key)) {
          return 'La question $i manque le champ "$key".';
        }
      }
      final type = q['type'] as String?;
      if (!['factuelle', 'analyse', 'synthese'].contains(type)) {
        return 'Le type de la question $i doit être "factuelle", "analyse" ou "synthese".';
      }
    }

    final avis = json['cas_avis_auteur'] as Map<String, dynamic>?;
    if (avis == null) return 'Le champ "cas_avis_auteur" doit être un objet.';
    if (!avis.containsKey('applicable')) {
      return 'Le champ "cas_avis_auteur.applicable" est manquant.';
    }
    final applicable = avis['applicable'] as bool?;
    if (applicable == true) {
      if (!avis.containsKey('these') || !avis.containsKey('limites')) {
        return 'Lorsque "cas_avis_auteur.applicable" est true, "these" et "limites" sont obligatoires.';
      }
      final these = avis['these'] as Map<String, dynamic>?;
      if (these == null ||
          !these.containsKey('idee') ||
          !these.containsKey('arguments')) {
        return 'Le champ "these" doit contenir "idee" et "arguments".';
      }
      final limites = avis['limites'] as Map<String, dynamic>?;
      if (limites == null ||
          !limites.containsKey('idee') ||
          !limites.containsKey('arguments')) {
        return 'Le champ "limites" doit contenir "idee" et "arguments".';
      }
    }

    final controle = json['controle'] as Map<String, dynamic>?;
    if (controle == null) return 'Le champ "controle" est invalide.';
    final requiredControle = [
      'analyse_document_complete',
      'espace_identifie',
      'questions_dans_ordre',
      'localisations_verifiees',
      'analyse_geographique',
      'document_analyse',
      'paraphrase_excessive',
      'chiffres_inventes',
      'dissertation_complete'
    ];
    for (final key in requiredControle) {
      if (!controle.containsKey(key)) {
        return 'Le champ "controle.$key" est manquant.';
      }
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
      return 'Prof IA n’a pas reçu une correction dans le format attendu. Réessaie avec ton texte.';
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
                    color: orangeDark,
                    size: 18,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Prof IA est spécialisé en exploitation de texte géographique. '
                      'Envoie un document suivi de questions pour obtenir une analyse structurée.',
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
  // TOP BAR (inchangée)
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
                  'Exploitation de texte géographique',
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
              color: orange.withOpacity(.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 15,
                  color: orange,
                ),
                SizedBox(width: 5),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: orangeDark,
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
  // HERO (inchangé)
  // ==========================================================

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(23, 24, 23, 23),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A8C5C), Color(0xFF087A4A)],
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
                        Icons.public_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'ATELIER GÉOGRAPHIE',
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
                  'Décrypte le texte.\nConstruis ton analyse.',
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
                  'Prof IA décortique le document géographique et te guide pas à pas vers une exploitation complète.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.90),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _heroBadge(Icons.location_on_rounded, 'ESPACE'),
                    const SizedBox(width: 8),
                    _heroBadge(Icons.insights_rounded, 'PHÉNOMÈNES'),
                    const SizedBox(width: 8),
                    _heroBadge(Icons.question_answer_rounded, 'QUESTIONS'),
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
  // COMPOSITEUR (avec bouton OCR)
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
                      color: orange.withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: orangeDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Le texte géographique',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: texte,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Colle le document et les éventuelles questions.',
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
                        'Exemple :\n« La Côte d’Ivoire, premier producteur mondial de cacao, connaît une forte croissance urbaine… »',
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
                      'Un texte précis avec des questions donne une analyse plus ciblée.',
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
                  // Bouton OCR
                  GestureDetector(
                    onTap: _isOcrProcessing ? null : _pickImageForOcr,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: orange.withOpacity(.10),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: orange.withOpacity(.15),
                        ),
                      ),
                      child: _isOcrProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(orangeDark),
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: orangeDark,
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
                  // Bouton Analyser
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
                    'Lecture du document • repérage des espaces • analyse des phénomènes',
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
                valueColor: AlwaysStoppedAnimation(orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // ERREUR / QUESTION INAPPROPRIÉE (inchangée)
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
                  'Désolé, je suis là pour t’aider à travailler ton exploitation de texte géographique.',
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
                    color: orangeDark,
                    size: 18,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Envoie un document géographique (article, extrait, rapport…) pour commencer.',
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
  // RÉSULTAT PRINCIPAL (inchangé, structure spécifique)
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
          _buildDocumentSection(result),
          const SizedBox(height: 15),
          _buildDecryptageSection(result),
          const SizedBox(height: 15),
          _buildQuestionsSection(result),
          const SizedBox(height: 15),
          _buildAvisAuteurSection(result),
          const SizedBox(height: 15),
          _buildControleSection(result),
        ],
      ),
    );
  }

  // ==========================================================
  // HEADER RÉSULTAT
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
                'Exploitation du document',
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
            color: orange.withOpacity(.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: orange,
                size: 15,
              ),
              SizedBox(width: 5),
              Text(
                'ANALYSÉ',
                style: TextStyle(
                  color: orangeDark,
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
  // SECTION DOCUMENT – inchangée
  // ==========================================================

  Widget _buildDocumentSection(Map<String, dynamic> result) {
    final doc = Map<String, dynamic>.from(result['document'] ?? {});
    return _sectionContainer(
      accent: orange,
      icon: Icons.public_rounded,
      label: 'DOCUMENT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Titre', doc['titre']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Nature', doc['nature']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Origine', doc['origine']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Date', doc['date']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Auteur', doc['auteur']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Espace étudié', doc['espace_etudie']?.toString() ?? ''),
          const SizedBox(height: 12),
          _miniLabel('Contexte géographique'),
          const SizedBox(height: 4),
          _textBlock(doc['contexte_geographique']),
          const SizedBox(height: 12),
          _miniLabel('Thème'),
          const SizedBox(height: 4),
          _textBlock(doc['theme']),
          const SizedBox(height: 12),
          _miniLabel('Idée principale'),
          const SizedBox(height: 4),
          _textBlock(doc['idee_principale']),
          const SizedBox(height: 12),
          _miniLabel('Intention'),
          const SizedBox(height: 4),
          _textBlock(doc['intention']),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SECTION DÉCRYPTAGE – inchangée
  // ==========================================================

  Widget _buildDecryptageSection(Map<String, dynamic> result) {
    final dec = Map<String, dynamic>.from(result['decryptage'] ?? {});
    final termes = (dec['termes_cles'] as List?) ?? [];
    final localisations = (dec['localisations'] as List?) ?? [];
    final phenomenes = (dec['phenomenes_geographiques'] as List?) ?? [];
    final facteurs = (dec['facteurs'] as List?) ?? [];
    final consequences = (dec['consequences'] as List?) ?? [];
    final limites = (dec['limites_du_document'] as List?) ?? [];

    return _sectionContainer(
      accent: orange,
      icon: Icons.search_rounded,
      label: 'DÉCRYPTAGE GÉOGRAPHIQUE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (termes.isNotEmpty) ...[
            _miniLabel('Termes clés'),
            const SizedBox(height: 4),
            for (var t in termes) _termeItem(t as Map<String, dynamic>),
            const SizedBox(height: 12),
          ],
          if (localisations.isNotEmpty) ...[
            _miniLabel('Localisations'),
            const SizedBox(height: 4),
            for (var l in localisations)
              _localisationItem(l as Map<String, dynamic>),
            const SizedBox(height: 12),
          ],
          if (phenomenes.isNotEmpty) ...[
            _miniLabel('Phénomènes géographiques'),
            const SizedBox(height: 4),
            for (var p in phenomenes) _phenomeneItem(p as Map<String, dynamic>),
            const SizedBox(height: 12),
          ],
          if (facteurs.isNotEmpty) ...[
            _miniLabel('Facteurs'),
            const SizedBox(height: 4),
            for (var f in facteurs) _facteurItem(f as Map<String, dynamic>),
            const SizedBox(height: 12),
          ],
          if (consequences.isNotEmpty) ...[
            _miniLabel('Conséquences'),
            const SizedBox(height: 4),
            for (var c in consequences)
              _consequenceItem(c as Map<String, dynamic>),
            const SizedBox(height: 12),
          ],
          if (limites.isNotEmpty) ...[
            _miniLabel('Limites du document'),
            const SizedBox(height: 4),
            for (var l in limites) _limiteItem(l as Map<String, dynamic>),
          ],
        ],
      ),
    );
  }

  Widget _termeItem(Map<String, dynamic> terme) {
    final nom = terme['terme']?.toString() ?? '';
    final sens = terme['sens_dans_le_contexte']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right_rounded, color: orange, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$nom : ',
                    style: const TextStyle(
                      color: orangeDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: sens,
                    style: const TextStyle(
                      color: texteSecondaire,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _localisationItem(Map<String, dynamic> loc) {
    final lieu = loc['lieu']?.toString() ?? '';
    final localisation = loc['localisation']?.toString() ?? '';
    final role = loc['role_geographique']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lieu,
            style: const TextStyle(
              color: orangeDark,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Localisation : $localisation',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 11,
            ),
          ),
          Text(
            'Rôle : $role',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _phenomeneItem(Map<String, dynamic> phenomene) {
    final nom = phenomene['phenomene']?.toString() ?? '';
    final explication = phenomene['explication']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right_rounded, color: vert, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$nom : ',
                    style: const TextStyle(
                      color: vertDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: explication,
                    style: const TextStyle(
                      color: texteSecondaire,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _facteurItem(Map<String, dynamic> facteur) {
    final nom = facteur['facteur']?.toString() ?? '';
    final explication = facteur['explication']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right_rounded, color: jaune, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$nom : ',
                    style: const TextStyle(
                      color: texte,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: explication,
                    style: const TextStyle(
                      color: texteSecondaire,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _consequenceItem(Map<String, dynamic> consequence) {
    final nom = consequence['consequence']?.toString() ?? '';
    final explication = consequence['explication']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right_rounded, color: orange, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$nom : ',
                    style: const TextStyle(
                      color: orangeDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: explication,
                    style: const TextStyle(
                      color: texteSecondaire,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _limiteItem(Map<String, dynamic> limite) {
    final text = limite.values.isNotEmpty ? limite.values.first.toString() : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: orange, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: texteSecondaire,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION QUESTIONS – inchangée
  // ==========================================================

  Widget _buildQuestionsSection(Map<String, dynamic> result) {
    final questions = (result['questions'] as List?) ?? [];
    return _sectionContainer(
      accent: vert,
      icon: Icons.question_answer_rounded,
      label: 'QUESTIONS ET RÉPONSES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < questions.length; i++)
            _buildQuestionItem(questions[i] as Map<String, dynamic>, i + 1),
        ],
      ),
    );
  }

  Widget _buildQuestionItem(Map<String, dynamic> q, int index) {
    final numero = q['numero']?.toString() ?? '$index';
    final question = q['question']?.toString() ?? '';
    final type = q['type']?.toString() ?? '';
    final reponse = q['reponse']?.toString() ?? '';
    final justification = q['justification']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: vert,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$numero',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(
                    color: texte,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: vert.withOpacity(.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Type : $type',
              style: TextStyle(
                color: vertDark,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _miniLabel('Réponse'),
          const SizedBox(height: 4),
          Text(
            reponse,
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (justification.isNotEmpty) ...[
            const SizedBox(height: 8),
            _miniLabel('Justification'),
            const SizedBox(height: 4),
            Text(
              justification,
              style: const TextStyle(
                color: texteSecondaire,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION AVIS AUTEUR – inchangée
  // ==========================================================

  Widget _buildAvisAuteurSection(Map<String, dynamic> result) {
    final avis = Map<String, dynamic>.from(result['cas_avis_auteur'] ?? {});
    final applicable = avis['applicable'] as bool? ?? false;

    if (!applicable) {
      return const SizedBox.shrink();
    }

    final these = Map<String, dynamic>.from(avis['these'] ?? {});
    final limites = Map<String, dynamic>.from(avis['limites'] ?? {});

    return _sectionContainer(
      accent: jaune,
      icon: Icons.thumbs_up_down_rounded,
      label: 'AVIS SUR L’AUTEUR',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniLabel('Thèse (points d’accord)'),
          const SizedBox(height: 4),
          Text(
            these['idee']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          if (these['arguments'] is List)
            for (var arg in these['arguments'] as List)
              _argumentItem(arg.toString()),
          const SizedBox(height: 12),
          _miniLabel('Limites (nuances)'),
          const SizedBox(height: 4),
          Text(
            limites['idee']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          if (limites['arguments'] is List)
            for (var arg in limites['arguments'] as List)
              _argumentItem(arg.toString()),
        ],
      ),
    );
  }

  Widget _argumentItem(String arg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right_rounded, color: orange, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              arg,
              style: const TextStyle(
                color: texteSecondaire,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION CONTRÔLE – inchangée
  // ==========================================================

  Widget _buildControleSection(Map<String, dynamic> result) {
    final controle = Map<String, dynamic>.from(result['controle'] ?? {});
    return _sectionContainer(
      accent: orange,
      icon: Icons.checklist_rounded,
      label: 'CONTRÔLE DE QUALITÉ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _controleItem('Analyse du document complète',
              controle['analyse_document_complete']),
          _controleItem('Espace identifié', controle['espace_identifie']),
          _controleItem(
              'Questions dans l’ordre', controle['questions_dans_ordre']),
          _controleItem(
              'Localisations vérifiées', controle['localisations_verifiees']),
          _controleItem(
              'Analyse géographique', controle['analyse_geographique']),
          _controleItem('Document analysé', controle['document_analyse']),
          _controleItem(
              'Paraphrase excessive', controle['paraphrase_excessive'],
              invert: true),
          _controleItem('Chiffres inventés', controle['chiffres_inventes'],
              invert: true),
          _controleItem(
              'Dissertation complète', controle['dissertation_complete'],
              invert: true),
        ],
      ),
    );
  }

  Widget _controleItem(String label, dynamic value, {bool invert = false}) {
    final boolValue = value as bool? ?? false;
    final isOk = invert ? !boolValue : boolValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isOk ? orange : Colors.red.shade400,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: texte,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPOSANTS UI GÉNÉRIQUES
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
}
