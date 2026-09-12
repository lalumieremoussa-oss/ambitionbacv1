import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'quiz_review_page.dart';

class QuizPage extends StatefulWidget {
  final Map<String, dynamic> quizData;
  final String sectionId;
  final String matiere;

  const QuizPage({
    required this.quizData,
    required this.sectionId,
    required this.matiere,
    super.key,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with TickerProviderStateMixin {
  // --- Données et État du Quiz ---
  late final List<Map<String, dynamic>> questions;
  int currentIndex = 0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AssetSource _successSound = AssetSource('son/success.mp3');
  final AssetSource _errorSound = AssetSource('son/error.mp3');
  bool isMuted = false;
  bool _handlingTimeUp = false;

  static const int totalSeconds = 75;
  int remainingSeconds = totalSeconds;
  Timer? _timer;
  late AnimationController _animController;
  late Animation<double> _animation;

  int totalAttempts = 0;
  int totalErrors = 0;
  Map<int, int> attemptsPerQuestion = {};

  bool questionLocked = false;
  bool quizEnded = false;
  // Variables spécifiques au QCM
  int? selectedAnswerIndex;
  bool? isLastAnswerCorrect;

  // Hive box
  Box? statsBox;

  // --- Variables spécifiques aux types de questions (Langue/Universel) ---
  final TextEditingController _shortAnswerController = TextEditingController();
  List<String> availableWords = [];
  List<String> currentPhrase = [];
  String? correctPhrase;

  @override
  void initState() {
    super.initState();

    final Map<String, dynamic> questionsMap =
        widget.quizData['questions'] as Map<String, dynamic>;
    questions =
        questionsMap.entries.map((entry) {
          return {'id': entry.key, ...(entry.value as Map<String, dynamic>)};
        }).toList();

    _animController =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: totalSeconds),
          )
          ..addListener(() {
            setState(() {
              remainingSeconds = (totalSeconds * _animation.value).ceil().clamp(
                0,
                totalSeconds,
              );
            });
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              if (!quizEnded) {
                _onTimeUp();
              }
            }
          });

    _animation = Tween<double>(begin: 1.0, end: 0.0).animate(_animController);

    _initHiveAndLoadProgress();
    _loadQuestionData();
    _startTimer();
  }

  void _initHiveAndLoadProgress() {
    try {
      statsBox =
          Hive.isBoxOpen('userStatsBox') ? Hive.box('userStatsBox') : null;

      if (statsBox != null) {
        final String key = 'progress_${widget.sectionId}';
        final savedProgress = statsBox!.get(key);

        if (savedProgress != null) {
          currentIndex = savedProgress['currentIndex'] as int;
          totalErrors = savedProgress['totalErrors'] as int;
          totalAttempts = savedProgress['totalAttempts'] as int;
          attemptsPerQuestion = Map<int, int>.from(
            savedProgress['attemptsPerQuestion'] ?? {},
          );
          remainingSeconds = savedProgress['remainingSeconds'] as int;
          final double startValue = remainingSeconds / totalSeconds;
          _animController.value = 1.0 - startValue;
        }
      }
    } catch (_) {
      statsBox = null;
    }
  }

  // Gère le cas où 'type' est absent en utilisant 'QCM' par défaut.
  void _loadQuestionData() {
    if (currentIndex >= questions.length) return;
    final question = questions[currentIndex];
    // FIX: Utilise 'QCM' par défaut
    final String type = question['type'] as String? ?? 'QCM';

    // Réinitialisation des variables spécifiques
    if (type == 'short_answer') {
      _shortAnswerController.clear();
      correctPhrase = question['bonne réponse'] as String;
    } else if (type == 'drag_and_drop') {
      currentPhrase.clear();
      final List<dynamic> wordsList = question['réponses'] as List<dynamic>;
      availableWords = wordsList.cast<String>().toList()..shuffle();
      correctPhrase = question['bonne réponse'] as String;
    } else {
      // Reset pour QCM (et par défaut)
      selectedAnswerIndex = null;
      isLastAnswerCorrect = null;
    }

    questionLocked = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    _audioPlayer.dispose();
    _shortAnswerController.dispose();
    super.dispose();
  }

  // --- Logique du Timer et Audio ---
  void _startTimer({bool reset = false}) {
    _timer?.cancel();
    if (reset) {
      _animController.reset();
      _animController.forward();
      return;
    }
    if (_animController.isCompleted) {
      _animController.reset();
    }
    _animController.forward();
  }

  void _stopTimer() {
    _timer?.cancel();
    _animController.stop();
    remainingSeconds = (totalSeconds * _animation.value).ceil().clamp(
      0,
      totalSeconds,
    );
  }

  void _onTimeUp() {
    if (_handlingTimeUp) return;
    _handlingTimeUp = true;
    if (mounted) {
      setState(() {
        totalErrors++;
        totalAttempts++;
        attemptsPerQuestion[currentIndex] =
            (attemptsPerQuestion[currentIndex] ?? 0) + 1;
      });
    }

    _playError();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) {
        _handlingTimeUp = false;
        return;
      }
      _animController.reset();
      _handlingTimeUp = false;
      _startTimer(reset: true);
    });
  }

  Future<void> _playSuccess() async {
    if (isMuted) return;
    await _audioPlayer.stop();
    await _audioPlayer.play(_successSound, mode: PlayerMode.lowLatency);
  }

  Future<void> _playError() async {
    if (isMuted) return;
    // On arrête d'abord pour réinitialiser le flux
    await _audioPlayer.stop();
    // On joue le son
    await _audioPlayer.play(_errorSound, mode: PlayerMode.lowLatency);
  }

  void _toggleMute() {
    setState(() {
      isMuted = !isMuted;
    });
    if (isMuted) {
      _audioPlayer.stop();
    }
  }

  // --- Logique de Gestion des Réponses ---

  void _moveToNextQuestion() {
    if (currentIndex >= questions.length - 1) {
      Future.delayed(const Duration(milliseconds: 1000), _finishQuiz);
      return;
    }

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        currentIndex++;
        _loadQuestionData();
      });
      _animController.reset();
      _startTimer(reset: true);
    });
  }

  void _handleIncorrectAnswer() {
    totalErrors++;
    _playError();

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        questionLocked = false;

        final String type = questions[currentIndex]['type'] as String? ?? 'QCM';

        if (type == 'drag_and_drop') {
          availableWords.addAll(currentPhrase);
          currentPhrase.clear();
          availableWords.shuffle();
        } else if (type == 'short_answer') {
          _shortAnswerController.clear();
          isLastAnswerCorrect = null; // Retire le feedback rouge/vert
        } else if (type == 'QCM') {
          selectedAnswerIndex = null;
          isLastAnswerCorrect = null;
        }
      });
      _startTimer(reset: true);
    });
  }

  // 1. Gestion du QCM
  void _onAnswerTapQCM(int answerIndex) async {
    if (quizEnded || questionLocked) return;

    totalAttempts++;
    attemptsPerQuestion[currentIndex] =
        (attemptsPerQuestion[currentIndex] ?? 0) + 1;

    final question = questions[currentIndex];
    final Map<String, dynamic> optionsMap =
        question['réponses'] as Map<String, dynamic>;
    final String correctLabel = question['bonne réponse'] as String;

    final List<String> optionKeys = optionsMap.keys.toList();
    final int correctIndex = optionKeys.indexOf(correctLabel);

    final bool isCorrect = correctIndex == answerIndex;

    setState(() {
      selectedAnswerIndex = answerIndex;
      isLastAnswerCorrect = isCorrect;
      questionLocked = true;
    });

    if (isCorrect) {
      await _playSuccess();
      _stopTimer();
      _moveToNextQuestion();
    } else {
      _handleIncorrectAnswer();
    }
  }

  // 2. Gestion de la Réponse Courte (`short_answer`)
  void _submitShortAnswer() async {
    if (quizEnded || questionLocked) return;

    final userAnswer = _shortAnswerController.text.trim();
    final correctAnswer = questions[currentIndex]['bonne réponse'] as String;

    totalAttempts++;
    attemptsPerQuestion[currentIndex] =
        (attemptsPerQuestion[currentIndex] ?? 0) + 1;

    // Comparaison (insensible à la casse)
    final bool isCorrect =
        userAnswer.toLowerCase() == correctAnswer.toLowerCase();

    setState(() {
      questionLocked = true;
      isLastAnswerCorrect = isCorrect; // Feedback pour short_answer
    });

    if (isCorrect) {
      await _playSuccess();
      _stopTimer();
      _moveToNextQuestion();
    } else {
      _handleIncorrectAnswer();
    }
  }

  // 3. Gestion du Glisser-Déposer (`drag_and_drop`) - Soumission
  void _submitDragAndDrop() async {
    if (quizEnded || questionLocked) return;

    final userAnswer = currentPhrase.join(' ');
    final correctAnswer = correctPhrase!;

    totalAttempts++;
    attemptsPerQuestion[currentIndex] =
        (attemptsPerQuestion[currentIndex] ?? 0) + 1;

    // Comparaison stricte
    final bool isCorrect = userAnswer == correctAnswer;

    setState(() {
      questionLocked = true;
      isLastAnswerCorrect = isCorrect; // Feedback pour drag_and_drop
    });

    if (isCorrect) {
      await _playSuccess();
      _stopTimer();
      _moveToNextQuestion();
    } else {
      _handleIncorrectAnswer();
    }
  }

  // --- Fin du Quiz et Sauvegarde ---
  double _calculateMoyenne() {
    if (totalAttempts == 0) return 0.0;
    return (questions.length / totalAttempts) * 20.0;
  }

  Future<void> _finishQuiz() async {
    _stopTimer();
    if (mounted) setState(() => quizEnded = true);

    final moyenne = _calculateMoyenne();
    final String sectionIdentifier = widget.sectionId;
    String errorMessage = '';
    bool skipSave = false;

    try {
      if (statsBox != null) {
        final existingEntry = statsBox!.get(sectionIdentifier);

        if (existingEntry != null) {
          skipSave = true;
          errorMessage =
              "Ce quiz (ID: $sectionIdentifier) a déjà été enregistré localement (Hive).";
        } else {
          final Map<String, dynamic> statEntry = {
            'matiere': widget.matiere,
            'sectionId': sectionIdentifier,
            'score_questions': questions.length,
            'total_tentatives': totalAttempts,
            'erreurs': totalErrors,
            'date': DateTime.now().toIso8601String(),
            'moyenne': moyenne,
          };
          await statsBox!.put(sectionIdentifier, {
            ...statEntry,
            'pendingSync': true,
          });
          errorMessage =
              "Sauvegarde effectuée uniquement en local. La synchronisation aura lieu lors de la prochaine vérification.";
        }
      } else {
        errorMessage =
            "Erreur: La boîte Hive n'est pas disponible. Résultat non enregistré.";
      }
    } catch (e) {
      errorMessage = "Erreur de sauvegarde locale (Hive) : $e";
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String message;
        if (totalErrors == 0) {
          message =
              "🟢 Ho le génie, félicitations !\nTu as tout cassé, bravo champion !";
        } else if (totalErrors <= 2) {
          message =
              "🟢 Excellent, tu es un génie. Tu travailles trop propre. Chapeau !";
        } else if (totalErrors <= 5) {
          message =
              "🟡 Bravo, tu as capté la leçon bien même. Tu es sur la bonne route. Continue seulement !";
        } else if (totalErrors <= 8) {
          message =
              "🟡 Le niveau est là, mais faut pas dormir ! Resserre un peu les boulons et tu vas voler haut !";
        } else if (totalErrors <= 10) {
          message =
              "🟠 Résultat passable mais tu peux faire mieux. Beaucoup de courage  !";
        } else if (totalErrors <= 13) {
          message =
              "🟠 Yako boss ! 🟠 « Yako boss ! Tu as pris quelques coups, mais l’essentiel c’est de pas lâcher. Courage, on est ensemble !.";
        } else {
          message =
              "🔴 Faut pas djô, faut rester ici ! Reprends les cours là doucement. Tu vas revenir plus chaud que braise ! C’est molo molo, poulet devient quelqu’un";
        }

        return AlertDialog(
          title: Text("${widget.matiere} — Résultats"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Questions réussies : ${questions.length}"),
              Text("Erreurs (mauvais choix + temps écoulé) : $totalErrors"),
              Text("Total tentatives : $totalAttempts"),
              const SizedBox(height: 8),
              Text(
                "Moyenne /20 : ${moyenne.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),

              if (skipSave || errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  "⚠️ $errorMessage",
                  style: TextStyle(
                    color:
                        (errorMessage.contains("Erreur") ||
                                errorMessage.contains("Duplicata"))
                            ? Colors.red
                            : Colors.orange,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (context) => QuizReviewPage(
                          quizData: widget.quizData,
                          matiere: widget.matiere,
                        ),
                  ),
                );
              },
              child: const Text("Réviser ce quiz"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text(
                "Retour aux sections",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPauseDialog() async {
    _stopTimer();

    final res = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Pause"),
            content: Text(
              "Quiz en pause (Temps restant: ${remainingSeconds}s). Reprendre ?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(_, false),
                child: const Text("Quitter"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(_, true),
                child: const Text("Reprendre"),
              ),
            ],
          ),
    );

    if (res == true) {
      _startTimer();
    } else {
      if (statsBox != null) {
        final String key = 'progress_${widget.sectionId}';
        statsBox!.put(key, {
          'currentIndex': currentIndex,
          'totalErrors': totalErrors,
          'totalAttempts': totalAttempts,
          'attemptsPerQuestion': attemptsPerQuestion,
          'remainingSeconds': remainingSeconds,
        });
      }
      Navigator.of(context).pop();
    }
  }

  // --- Widgets de Rendu des Questions ---
  // 1. Rendu du QCM (Texte simple)
  Widget _buildQCMBody(Map<String, dynamic> question, double bodyHeight) {
    final Map<String, dynamic> optionsMap =
        question['réponses'] as Map<String, dynamic>;
    final List<String> options = optionsMap.values.cast<String>().toList();
    final String? imagePath = question['image'];
    final bool hasImage = imagePath != null && imagePath.isNotEmpty;
    double questionTextRatio;
    double answersRatio;
    double imageHeight = 0;
    if (hasImage) {
      questionTextRatio = 0.25;
      imageHeight = bodyHeight * 0.35;
      answersRatio = 0.40;
    } else {
      questionTextRatio = 0.35;
      answersRatio = 0.65;
    }
    final double questionTextHeight = bodyHeight * questionTextRatio;
    final double answersHeight = bodyHeight * answersRatio;

    return Column(
      children: [
        // --- ZONE 1 : TEXTE DE LA QUESTION ---
        SizedBox(
          height: questionTextHeight,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF43A047), width: 4),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Center(
                child: SingleChildScrollView(
                  child: Text(
                    question['question'] as String,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),

        // --- ZONE 2 : IMAGE (Affichée uniquement si présente) ---
        if (hasImage)
          SizedBox(
            height: imageHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(imagePath, fit: BoxFit.contain),
                ),
              ),
            ),
          ),

        // --- ZONE 3 : RÉPONSES ---
        SizedBox(
          height: answersHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(options.length, (i) {
                final String label = String.fromCharCode(65 + i);
                final String text = options[i].toString();

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: InkWell(
                      onTap: questionLocked ? null : () => _onAnswerTapQCM(i),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient:
                              i == selectedAnswerIndex &&
                                      isLastAnswerCorrect == true
                                  ? const LinearGradient(
                                    colors: [
                                      Color(0xFF4CAF50),
                                      Color(0xFF1B5E20),
                                    ],
                                  )
                                  : i == selectedAnswerIndex &&
                                      isLastAnswerCorrect == false
                                  ? const LinearGradient(
                                    colors: [
                                      Color(0xFFE57373),
                                      Color(0xFFB71C1C),
                                    ],
                                  )
                                  : const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF7ED957),
                                      Color(0xFF43A047),
                                    ],
                                  ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                i == selectedAnswerIndex &&
                                        isLastAnswerCorrect != null
                                    ? (isLastAnswerCorrect!
                                        ? Colors.green.shade900
                                        : Colors.red.shade900)
                                    : const Color(0xFF43A047),
                            width: 4,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                text,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  // 2. Rendu de la Réponse Courte (`short_answer`)
  Widget _buildShortAnswerBody(
    Map<String, dynamic> question,
    double bodyHeight,
  ) {
    const double questionTextRatio = 0.35;
    const double answerAreaRatio = 0.65;
    final double questionTextHeight = bodyHeight * questionTextRatio;
    final double answerAreaHeight = bodyHeight * answerAreaRatio;

    return Column(
      children: [
        // Zone Question Text (35%)
        SizedBox(
          height: questionTextHeight,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF43A047), width: 4),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  question['question'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),

        // Zone Réponse (65%)
        SizedBox(
          height: answerAreaHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 10.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _shortAnswerController,
                      enabled: !questionLocked,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Écrivez votre réponse ici',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        fillColor: Colors.white,
                        filled: true,
                        prefixIcon: const Icon(
                          Icons.edit,
                          color: Color(0xFFFF8C00),
                        ),
                      ),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: questionLocked ? null : _submitShortAnswer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text(
                        'Envoyer',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (questionLocked && isLastAnswerCorrect != null)
                      Text(
                        isLastAnswerCorrect!
                            ? '🟢 Correct !'
                            : '🔴 Faux. La bonne réponse était: ${question['bonne réponse']}',
                        style: TextStyle(
                          color:
                              isLastAnswerCorrect!
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 3. Rendu du Glisser-Déposer (`drag_and_drop`)
  Widget _buildDragAndDropBody(
    Map<String, dynamic> question,
    double bodyHeight,
  ) {
    const double questionTextRatio = 0.20;
    const double phraseAreaRatio = 0.25;
    const double wordsAreaRatio = 0.35;
    const double buttonAreaRatio = 0.20;

    final double questionTextHeight = bodyHeight * questionTextRatio;
    final double phraseAreaHeight = bodyHeight * phraseAreaRatio;
    final double wordsAreaHeight = bodyHeight * wordsAreaRatio;
    final double buttonAreaHeight = bodyHeight * buttonAreaRatio;

    return Column(
      children: [
        // 1. Zone Question Text (20%)
        SizedBox(
          height: questionTextHeight,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF43A047), width: 4),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  question['question'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),

        // 2. Zone de construction de la phrase (25%)
        SizedBox(
          height: phraseAreaHeight,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: DragTarget<String>(
              builder: (context, candidateData, rejectedData) {
                return Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 80),
                  decoration: BoxDecoration(
                    color:
                        candidateData.isNotEmpty
                            ? Colors.green.shade50
                            : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color:
                          candidateData.isNotEmpty
                              ? Colors.green
                              : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  padding: const EdgeInsets.all(12.0),
                  child:
                      currentPhrase.isEmpty
                          ? Center(
                            child: Text(
                              "Glissez et déposez les mots ici",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                          : Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            alignment: WrapAlignment.center,
                            children:
                                currentPhrase.asMap().entries.map((entry) {
                                  final int index = entry.key;
                                  final String word = entry.value;
                                  return ActionChip(
                                    label: Text(
                                      word,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    onPressed:
                                        questionLocked
                                            ? null
                                            : () {
                                              setState(() {
                                                currentPhrase.removeAt(index);
                                                availableWords.add(word);
                                                availableWords.shuffle();
                                              });
                                            },
                                    backgroundColor: Colors.lightGreen.shade200,
                                  );
                                }).toList(),
                          ),
                );
              },
              onWillAcceptWithDetails: (data) => !questionLocked,
              onAcceptWithDetails: (details) {
                if (!questionLocked) {
                  setState(() {
                    currentPhrase.add(details.data);
                    availableWords.remove(details.data);
                  });
                }
              },
            ),
          ),
        ),

        // 3. Zone des mots disponibles (35%)
        SizedBox(
          height: wordsAreaHeight,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  alignment: WrapAlignment.center,
                  children:
                      availableWords.map((word) {
                        return Draggable<String>(
                          data: word,
                          feedback: Material(
                            elevation: 4.0,
                            child: Chip(
                              label: Text(
                                word,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.blue,
                                ),
                              ),
                              backgroundColor: Colors.blue.shade100,
                            ),
                          ),
                          childWhenDragging: Chip(
                            label: Text(
                              word,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            backgroundColor: Colors.grey.shade200,
                          ),
                          child: Chip(
                            label: Text(
                              word,
                              style: const TextStyle(fontSize: 16),
                            ),
                            backgroundColor: const Color(0xFFFF8C00),
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                        );
                      }).toList(),
                ),
              ),
            ),
          ),
        ),

        // 4. Bouton d'envoi (20%)
        SizedBox(
          height: buttonAreaHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 8.0,
            ),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed:
                      questionLocked || currentPhrase.isEmpty
                          ? null
                          : _submitDragAndDrop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'Valider la phrase',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                if (questionLocked)
                  Text(
                    currentPhrase.join(' ') == correctPhrase
                        ? '🟢 Phrase correcte !'
                        : '🔴 Incorrecte. La phrase correcte était: $correctPhrase',
                    style: TextStyle(
                      color:
                          currentPhrase.join(' ') == correctPhrase
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- UI principale (Sélection du Body) ---
  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            "Erreur: Aucune question n'a pu être chargée pour ce quiz.",
          ),
        ),
      );
    }

    final question = questions[currentIndex];
    // Gère le cas où le type est absent en utilisant 'QCM' par défaut.
    final String questionType = question['type'] as String? ?? 'QCM';

    final media = MediaQuery.of(context);
    const double appBarHeight = 100;
    final double bodyHeight =
        media.size.height - media.padding.top - appBarHeight;

    Widget bodyContent;

    switch (questionType) {
      case 'drag_and_drop':
        bodyContent = _buildDragAndDropBody(question, bodyHeight);
        break;
      case 'short_answer':
        bodyContent = _buildShortAnswerBody(question, bodyHeight);
        break;
      case 'QCM':
      default:
        bodyContent = _buildQCMBody(question, bodyHeight);
        break;
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _showPauseDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF4F0),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(appBarHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: const Color(0xFFFF8C00),
                centerTitle: true,
                title: Column(
                  children: [
                    Text(
                      widget.matiere,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 16.0,
                      ),
                    ),
                    Text(
                      "Question ${currentIndex + 1}/${questions.length} (${questionType})",
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _showPauseDialog,
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Chip(
                      backgroundColor: Colors.red,
                      label: Text(
                        "Erreur: $totalErrors",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Chip(
                      backgroundColor: Colors.pink,
                      label: Text(
                        "${remainingSeconds}s",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleMute,
                    icon: Icon(
                      isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              // Barre de progression animée du Minuteur
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return LinearProgressIndicator(
                    value: _animation.value,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color.lerp(Colors.red, Colors.green, _animation.value)!,
                    ),
                    minHeight: 8.0,
                  );
                },
              ),
            ],
          ),
        ),
        body: Column(children: [Expanded(child: bodyContent)]),
      ),
    );
  }
}
