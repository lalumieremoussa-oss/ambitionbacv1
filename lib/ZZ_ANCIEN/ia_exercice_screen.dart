import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 👈 ajout
import 'deepseek_service.dart';
import 'document_extractor.dart';

class IaExerciceScreen extends StatefulWidget {
  final String matiereId;
  final String leconId;
  final String leconTitre;
  final String sectionId;
  final List<Map<String, dynamic>> sections;

  const IaExerciceScreen({
    super.key,
    required this.matiereId,
    required this.leconId,
    required this.leconTitre,
    required this.sectionId,
    required this.sections,
  });

  @override
  State<IaExerciceScreen> createState() => _IaExerciceScreenState();
}

class _IaExerciceScreenState extends State<IaExerciceScreen> {
  final DeepSeekService _ia = DeepSeekService();
  final TextEditingController _controller = TextEditingController();

  List<Map<String, dynamic>> _messages = [];
  late Box _iaBox;

  bool _isLoading = false;
  String _guide = "";
  bool _isProcessingImage = false;
  bool _isLoadingBoxAndGuide = true;
  bool _isPremium = false;

  String get _boxKey => 'chat_${widget.matiereId}_${widget.leconId}';

  @override
  void initState() {
    super.initState();
    _initialiserEcran();
  }

  Future<void> _initialiserEcran() async {
    setState(() => _isLoadingBoxAndGuide = true);

    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool('premium') ?? false;

    _iaBox = await Hive.openBox('IAbox');
    final List<dynamic>? localHistory = _iaBox.get(_boxKey);

    _guide = await DocumentExtractor.chargerGuideMethodologique(
      matiereId: widget.matiereId,
      leconId: widget.leconId,
    );

    // 4) Historique ou message d'accueil
    if (localHistory != null && localHistory.isNotEmpty) {
      _messages = List<Map<String, dynamic>>.from(
          localHistory.map((e) => Map<String, dynamic>.from(e)));
    } else {
      String accueil =
          "🤖 **Ambition+ IA** – ton professeur ivoirien sur mesure !\n\n"
          "Contrairement à ChatGPT, DeepSeek ou Gemini, qui sont des IA généralistes, "
          "moi, Ambition+ IA, j'ai été **spécialement entraîné** pour le système éducatif ivoirien. "
          "Je maîtrise les méthodologies et les démonstrations attendues par tes professeurs en classe "
          "et aux examens.\n\n"
          "📚 Les exercices doivent porter uniquement sur « ${widget.leconTitre} ».\n\n"
          "📸 Prends une photo (pas de manuscrit, sinon écris directement le sujet) ou "
          "choisis une image depuis ta galerie.\n\n"
          "⚠️ Je ne donne jamais la solution toute faite – je te guide avec la méthode ivoirienne, "
          "pas à pas, comme le ferait un bon professeur.\n\n"
          "✍️ **Quel exercice souhaites-tu travailler ?**";

      if (_guide.isEmpty) {
        accueil =
            "🤖 **Ambition+ IA** – ton professeur ivoirien sur mesure !\n\n"
            "Contrairement à ChatGPT, DeepSeek ou Gemini, qui sont des IA généralistes, "
            "moi, Ambition+ IA, j'ai été **spécialement entraîné** pour le système éducatif ivoirien. "
            "Je maîtrise les méthodologies et les démonstrations attendues par tes professeurs en classe "
            "et aux examens (BAC, BEPC, etc.).\n\n"
            "📸 Prends une photo (pas de manuscrit, sinon écris directement le sujet) ou "
            "choisis une image depuis ta galerie.\n\n"
            "⚠️ Je ne donne jamais la solution toute faite – je te guide avec la méthode ivoirienne, "
            "pas à pas, comme le ferait un bon professeur.\n\n"
            "✍️ **Quel exercice souhaites-tu travailler ?**";
      }
      _messages.add({'role': 'assistant', 'content': accueil});
      await _sauvegarderDansHive();
    }

    setState(() => _isLoadingBoxAndGuide = false);
  }

  Future<void> _sauvegarderDansHive() async {
    await _iaBox.put(_boxKey, _messages);
  }

  String _getPremiumBlockMessage() {
    return ("🙏 Désolé, je suis là pour soutenir les utilisateurs Premium. "
        "Si tu es prêt à recevoir mon aide 24h/24 sans limite, il te suffit de t'inscrire au Premium.\n\n"
        "🔥 **Offre exceptionnelle** : profite d'une réduction de **85%** pour 12 mois d'abonnement ! "
        "Mais dépêche-toi, le nombre de places est limité. Une fois le quota atteint, tu paieras beaucoup plus cher.\n\n"
        "✨ Et ce n'est pas tout : des fonctionnalités ultra-améliorées et d'autres surprises arrivent très bientôt pour les Premium. "
        "Ne rate pas cette chance !\n\n"
        "👉 Va t'inscrire maintenant et reviens me voir. À très bientôt ! 🚀");
  }

  // 🔒 Vérification Premium avant tout appel IA
  Future<bool> _checkPremiumAndBlockIfNeeded() async {
    if (!_isPremium) {
      // Ajouter le message d'assistant bloquant
      setState(() {
        _messages
            .add({'role': 'assistant', 'content': _getPremiumBlockMessage()});
        _isLoading = false;
        _isProcessingImage = false;
      });
      await _sauvegarderDansHive();
      return false;
    }
    return true;
  }

  // Méthode d'envoi de message (texte)
  Future<void> _envoyerMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': message});
      _isLoading = true;
    });
    _controller.clear();
    await _sauvegarderDansHive();

    // Vérification Premium
    final bool allowed = await _checkPremiumAndBlockIfNeeded();
    if (!allowed) return; // déjà bloqué avec message

    // Appel à l'IA
    await _envoyerAEtAfficherReponse(message);
  }

  // Traitement d'image (photo ou galerie)
  Future<void> _traiterExtractionImage(
      Future<String> Function() extractionTask) async {
    try {
      setState(() {
        _isProcessingImage = true;
        _isLoading = true;
      });

      final String extractedText = await extractionTask();

      if (extractedText.trim().isEmpty) {
        throw Exception(
            "Aucun texte n'a pu être extrait de l'image. Assure-toi que le document est bien lisible.");
      }

      setState(() {
        _messages.add({
          'role': 'user',
          'content':
              '📷 Exercice extrait par image :\n\n${extractedText.trim()}'
        });
      });
      await _sauvegarderDansHive();

      // Vérification Premium
      final bool allowed = await _checkPremiumAndBlockIfNeeded();
      if (!allowed) return; // déjà bloqué avec message

      // Appel à l'IA
      await _envoyerAEtAfficherReponse(extractedText);
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content':
              '❌ Erreur d\'analyse : ${e.toString().replaceAll('Exception:', '')}'
        });
        _isLoading = false;
        _isProcessingImage = false;
      });
      await _sauvegarderDansHive();
    }
  }

  // Méthodes d'appel IA (inchangées)
  Future<void> _envoyerAEtAfficherReponse(String texteUtilisateur) async {
    String systemPrompt;
    String userPrompt;

    const String formatInstruction = """
\n\n**RÈGLES DE FORMATAGE OBLIGATOIRES :**
- Utilise la syntaxe **Markdown** complète : titres (`#`, `##`), listes (`-`), gras (`**texte**`), italique (`*texte*`), etc.
- Ne donne jamais la solution brute. Sois pédagogique.
""";

    if (_guide.isNotEmpty) {
      systemPrompt =
          "Tu es un professeur patient. Tu disposes du guide méthodologique suivant:\n$_guide\n\n"
          "Tu ne dois répondre qu'aux questions en lien direct avec la leçon intitulée « ${widget.leconTitre} ».\n\n"
          "Si un élève te pose une question qui n'a **strictement aucun rapport** avec ce sujet, tu dois refuser poliment en répondant uniquement : 'Désolé, je ne peux répondre qu'aux questions sur ${widget.leconTitre}.'\n\n"
          "Utilise le guide pour guider l'élève. Ne mentionne pas explicitement le guide, mais applique ses consignes.\n\n"
          "Les réponses doivent être données intégralement : analyse du sujet, plan détaillé de la résolution (introduction , plan detaillé du dveloppement, conclusion ou reponses detaillé des questions dans cas de exploitation de texte en histoire geographie (si pas redaction) ou question simple qui n'est pas une redaction). Ne jamais répondre partiellement pour poser une question à l'utilisateur.\n\n"
          "$formatInstruction";
      userPrompt = "Voici l'exercice de l'élève : $texteUtilisateur";
    } else {
      systemPrompt = "Tu es un professeur expert en ${widget.matiereId}.\n\n"
          "Tu ne dois répondre qu'aux questions en lien direct avec la leçon intitulée « ${widget.leconTitre} ».\n\n"
          "Si un élève te pose une question qui n'a **strictement aucun rapport** avec ce sujet, tu dois refuser poliment en répondant uniquement : 'Désolé, je ne peux répondre qu'aux questions sur ${widget.leconTitre}.'\n\n"
          "Guide l'élève vers la solution en expliquant les concepts nécessaires. Ne mentionne pas explicitement le guide, mais applique ses consignes.\n\n"
          "Les réponses doivent être données intégralement : analyse du sujet, plan détaillé de la résolution (introduction , plan detaillé du dveloppement, conclusion ou reponses detaillé des questions dans cas de exploitation de texte en histoire geographie (si pas redaction) ou question simple qui n'est pas une redaction). Ne jamais répondre partiellement pour poser une question à l'utilisateur.\n\n"
          "$formatInstruction";
      userPrompt = "Exercice : $texteUtilisateur";
    }
    try {
      final reponse = await _ia.chatCompletion(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );

      setState(() {
        _messages.add({'role': 'assistant', 'content': reponse});
        _isLoading = false;
        _isProcessingImage = false;
      });
      await _sauvegarderDansHive();
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content':
              "❌ Une erreur est survenue lors de la communication avec l'IA. Réessaie."
        });
        _isLoading = false;
        _isProcessingImage = false;
      });
    }
  }

  // Wrappers pour photo et galerie
  Future<void> _prendrePhotoEtOCR() async {
    _traiterExtractionImage(() => DocumentExtractor.takePhotoAndExtractText());
  }

  Future<void> _choisirImageGalerieEtOCR() async {
    _traiterExtractionImage(
        () => DocumentExtractor.pickImageFromGalleryAndExtractText());
  }

  // Widgets d'affichage (inchangés)
  Widget _buildAssistantMessage(String rawContent) {
    final RegExp latexRegex = RegExp(
      r'(?<!\\)(\\\(.*?\\\))|(?<!\\)(\\\(.*?\\\))|(?<!\\)(\\\[.*?\\\])',
      dotAll: true,
    );
    final List<Widget> children = [];
    int lastIndex = 0;

    for (final match in latexRegex.allMatches(rawContent)) {
      if (match.start > lastIndex) {
        final textPart = rawContent.substring(lastIndex, match.start);
        if (textPart.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: textPart,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, color: Colors.black87),
                h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                listBullet:
                    const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
          );
        }
      }

      String formulaWithDelimiters = match.group(0)!;
      final bool isInline = formulaWithDelimiters.startsWith(r'\(');
      String cleanFormula =
          formulaWithDelimiters.substring(2, formulaWithDelimiters.length - 2);

      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Math.tex(
            cleanFormula,
            mathStyle: isInline ? MathStyle.text : MathStyle.display,
            textStyle: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
      );

      lastIndex = match.end;
    }

    if (lastIndex < rawContent.length) {
      final textPart = rawContent.substring(lastIndex);
      if (textPart.trim().isNotEmpty) {
        children.add(
          MarkdownBody(
            data: textPart,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 16, color: Colors.black87),
              h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              listBullet: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool inputsDisabled = _isLoading || _isProcessingImage;

    return Scaffold(
      appBar: AppBar(
        title: Text('🤖 Prof IA - ${widget.leconTitre}'),
        backgroundColor: const Color(0xFFFF8C00),
      ),
      body: _isLoadingBoxAndGuide
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFFFF8C00)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: isUser
                              ? SelectableText(
                                  msg['content']!,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 16),
                                )
                              : _buildAssistantMessage(msg['content']!),
                        ),
                      );
                    },
                  ),
                ),
                if (_isProcessingImage)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange.shade50,
                    child: const Row(
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFFFF8C00))),
                        SizedBox(width: 8),
                        Text('Analyse de l\'image et extraction du texte...'),
                      ],
                    ),
                  ),
                if (_isLoading && !_isProcessingImage)
                  const LinearProgressIndicator(color: Color(0xFFFF8C00)),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.camera_alt,
                            color: Colors.orange.shade700),
                        onPressed: inputsDisabled ? null : _prendrePhotoEtOCR,
                        tooltip: 'Prendre une photo en direct',
                      ),
                      IconButton(
                        icon: Icon(Icons.photo_library,
                            color: Colors.orange.shade700),
                        onPressed:
                            inputsDisabled ? null : _choisirImageGalerieEtOCR,
                        tooltip: 'Choisir depuis la galerie',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_isLoading,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: 'Tapez votre exercice...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: _isLoading
                                ? Colors.grey.shade300
                                : Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          onSubmitted: (_) => _envoyerMessage(_controller.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: const Color(0xFFFF8C00),
                        child: IconButton(
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 20),
                          onPressed: _isLoading
                              ? null
                              : () => _envoyerMessage(_controller.text),
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
