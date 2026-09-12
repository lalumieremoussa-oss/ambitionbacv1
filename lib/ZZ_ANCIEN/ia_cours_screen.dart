import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'deepseek_service.dart';
import 'document_extractor.dart';

class IaCoursScreen extends StatefulWidget {
  final String matiereId;
  final String leconId;
  final String leconTitre;

  const IaCoursScreen({
    super.key,
    required this.matiereId,
    required this.leconId,
    required this.leconTitre,
  });

  @override
  State<IaCoursScreen> createState() => _IaCoursScreenState();
}

class _IaCoursScreenState extends State<IaCoursScreen> {
  final DeepSeekService _ia = DeepSeekService();

  // ✅ Changement : final -> non-final
  List<Map<String, String>> _messages = [];
  final TextEditingController _questionController = TextEditingController();

  late Box _iaBox;

  String _guide = "";
  bool _isLoadingGuide = true;
  bool _isLoading = false;
  bool _isLoadingBox = true;

  String get _boxKey => 'cours_${widget.matiereId}_${widget.leconId}';

  @override
  void initState() {
    super.initState();
    _initialiserEcran();
  }

  Future<void> _initialiserEcran() async {
    setState(() => _isLoadingBox = true);

    _iaBox = await Hive.openBox('IAbox');
    final List<dynamic>? localHistory = _iaBox.get(_boxKey);

    _guide = await DocumentExtractor.chargerGuideMethodologique(
      matiereId: widget.matiereId,
      leconId: widget.leconId,
    );

    if (localHistory != null && localHistory.isNotEmpty) {
      _messages = List<Map<String, String>>.from(
          localHistory.map((e) => Map<String, String>.from(e)));
    } else {
      String accueil;
      if (_guide.isNotEmpty) {
        accueil =
            "👋 **Ambition+ IA**. Pose-moi ta question sur **${widget.leconTitre}**.";
      } else {
        accueil =
            "👋 **Ambition+ IA** – concernant le sujet « ${widget.leconTitre} ». Pose-moi ta question, je te guiderai.";
      }
      _messages.add({'role': 'assistant', 'content': accueil});
      await _sauvegarderDansHive();
    }

    setState(() {
      _isLoadingBox = false;
      _isLoadingGuide = false;
    });
  }

  Future<void> _sauvegarderDansHive() async {
    await _iaBox.put(_boxKey, _messages);
  }

  Future<void> _repondreALaQuestion(String question) async {
    if (question.trim().isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': question});
      _isLoading = true;
    });
    _questionController.clear();
    await _sauvegarderDansHive();

    const String formatInstruction = """
\n\n**RÈGLES DE FORMATAGE :**
- Utilise la syntaxe **Markdown** pour structurer ta réponse : titres (`#`, `##`), listes (`-`), gras (`**texte**`), etc.
- Pour toutes les formules mathématiques, encadre-les avec `\\( ... \\)` (inline) ou `\\[ ... \\]` (display).
- Sois pédagogique et précis.
""";

    String systemPrompt;
    String userPrompt;

    if (_guide.isNotEmpty) {
      systemPrompt =
          "Tu es un professeur patient. Tu disposes du guide méthodologique suivant:\n$_guide\n\n"
          "Ne réponds qu'aux questions en rapport avec « ${widget.leconTitre} ». "
          "Si la question est hors sujet, réponds poliment : 'Désolé, je ne peux répondre qu'aux questions sur ${widget.leconTitre}.'\n\n"
          "Utilise le guide pour répondre à l'élève. Ne mentionne pas explicitement le guide, mais applique ses consignes."
          "$formatInstruction";
      userPrompt = "Voici la question de l'élève : $question";
    } else {
      systemPrompt =
          "Tu es un professeur expert en ${widget.matiereId} (connaissances générales du programme). "
          "Ne réponds qu'aux questions en rapport avec « ${widget.leconTitre} ». "
          "Si la question est hors sujet, réponds poliment : 'Désolé, je ne peux répondre qu'aux questions sur ${widget.leconTitre}.'\n\n"
          "Réponds de façon pédagogique, avec des explications claires et des exemples."
          "$formatInstruction";
      userPrompt = "Question sur « ${widget.leconTitre} » : $question";
    }

    try {
      final reponse = await _ia.chatCompletion(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );

      setState(() {
        _messages.add({'role': 'assistant', 'content': reponse});
        _isLoading = false;
      });
      await _sauvegarderDansHive();
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': "❌ Une erreur est survenue. Réessaie."
        });
        _isLoading = false;
      });
      await _sauvegarderDansHive();
    }
  }

  Widget _buildAssistantMessage(String content) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 16, color: Colors.black87),
        h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        listBullet: const TextStyle(fontSize: 16, color: Colors.black87),
      ),
      builders: {
        'latex': LatexElementBuilder(
          textStyle: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('IA - ${widget.leconTitre}'),
        backgroundColor: const Color(0xFFFF8C00),
      ),
      body: _isLoadingBox
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)))
          : Column(
              children: [
                if (_isLoadingGuide)
                  const LinearProgressIndicator()
                else if (_guide.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.green.shade100,
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green.shade700, size: 16),
                        const SizedBox(width: 8),
                        const Text('Guide méthodologique disponible'),
                      ],
                    ),
                  ),
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
                                  style: const TextStyle(color: Colors.white),
                                )
                              : _buildAssistantMessage(msg['content']!),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _questionController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            hintText: 'Pose ta question...',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24)),
                            filled: true,
                            fillColor: _isLoading
                                ? Colors.grey.shade300
                                : Colors.grey.shade100,
                          ),
                          onSubmitted: (_) =>
                              _repondreALaQuestion(_questionController.text),
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
                              : () => _repondreALaQuestion(
                                  _questionController.text),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoading) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
