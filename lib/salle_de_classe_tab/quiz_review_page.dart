// 📁 lib/quiz_review_page.dart
import 'package:flutter/material.dart';


class QuizReviewPage extends StatelessWidget {
  final Map<String, dynamic> quizData;
  final String matiere;

  const QuizReviewPage({required this.quizData, required this.matiere, super.key});

  // --- Convertir Map<String, Map> en List<Map>
  List<Map<String, dynamic>> _getQuestionsList() {
    final Map<String, dynamic> questionsMap = quizData['questions'] as Map<String, dynamic>;
    return questionsMap.entries.map((entry) {
      return {
        'id': entry.key,
        ...(entry.value as Map<String, dynamic>),
      };
    }).toList();
  }

  Widget _buildText(String text, {required bool isAnswer, bool isCorrect = false}) {
    final Color textColor = isAnswer ? Colors.white : Colors.black;

    return Text(
      text,
      style: TextStyle(
        fontSize: isAnswer ? 14 : 16,
        fontWeight: isAnswer ? FontWeight.w600 : FontWeight.bold,
        color: textColor,
      ),
      // Justifier la question, aligner à gauche les réponses
      textAlign: isAnswer ? TextAlign.start : TextAlign.justify,
    );
  }

  @override
  Widget build(BuildContext context) {
    final questions = _getQuestionsList();

    // Sécurité au cas où la liste de questions serait vide
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text("Révision du Quiz : $matiere")),
        body: const Center(child: Text("Aucune question trouvée pour la révision.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      appBar: AppBar(
        title: Text("Révision du Quiz : $matiere", style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFFF8C00),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12.0),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final question = questions[index];
          // ✅ CORRECTION : Utilisation de 'as String' avec fallback robuste
          final String questionText = (question['question'] as String? ?? '');
          final String correctLabel = question['bonne réponse'] as String;
          final Map<String, dynamic> optionsMap = question['réponses'] as Map<String, dynamic>;
          
          final optionKeys = optionsMap.keys.toList();
          // ✅ CORRECTION : Assurer que toutes les valeurs sont des Strings pour la liste d'options
          final options = optionsMap.values.map((e) => e.toString()).toList(); 
          
          final correctIndex = optionKeys.indexOf(correctLabel);

          return Card(
            color: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Titre Question ---
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "Question ${index + 1}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // --- Texte de la question ---
                  _buildText(questionText, isAnswer: false),
                  const SizedBox(height: 15),

                  // --- Image (si présente) ---
                  if (question['image'] != null && (question['image'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            question['image'] as String, // Assurer le type String
                            fit: BoxFit.contain,
                            height: 150,
                          ),
                        ),
                      ),
                    ),

                  // --- Liste des réponses ---
                  ...List.generate(options.length, (i) {
                    final isCorrect = i == correctIndex;
                    final label = optionKeys[i];
                    final text = options[i];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          // Le vert foncé pour la réponse correcte
                          color: isCorrect ? const Color(0xFF4CAF50) : const Color(0xFF43A047).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                          // Bordure plus visible pour la bonne réponse
                          border: isCorrect ? Border.all(color: Colors.green.shade900, width: 3) : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$label. ",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Expanded(child: _buildText(text, isAnswer: true, isCorrect: isCorrect)),
                            if (isCorrect) const Icon(Icons.check_circle, color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}