import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ExercicesPage extends StatefulWidget {
  final String htmlPath; 
  final String sectionId;
  final String matiere; 

  const ExercicesPage({
    required this.htmlPath,
    required this.sectionId,
    required this.matiere,
    super.key
  });

  @override
  State<ExercicesPage> createState() => _ExercicesPageState();
}

class _ExercicesPageState extends State<ExercicesPage> {
  late final WebViewController _controller;
  bool _isSubmitted = false;
  Box? statsBox;

  @override
  void initState() {
    super.initState();
    statsBox = Hive.isBoxOpen('userStatsBox') ? Hive.box('userStatsBox') : null;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFF4F0))
      ..addJavaScriptChannel(
        'ExerciceChannel',
        onMessageReceived: (JavaScriptMessage message) {
          // Empêche les soumissions multiples si l'élève clique plusieurs fois
          if (!_isSubmitted) {
            try {
              final Map<String, dynamic> data = jsonDecode(message.message);
              _processResults(
                (data['score'] as num).toInt(), 
                (data['total'] as num).toInt()
              );
            } catch (e) {
              debugPrint("Erreur format JSON reçu: ${message.message}");
            }
          }
        },
      )
      ..loadFlutterAsset(widget.htmlPath);
  }

  void _processResults(int score, int total) {
    setState(() => _isSubmitted = true);

    // Calcul de la moyenne sur 20
    double moyenne = total > 0 ? (score / total) * 20.0 : 0.0;
    int erreurs = total - score;

    _saveToHive(score, total, erreurs, moyenne);
    _showResultDialog(score, total, erreurs, moyenne);
  }

  Future<void> _saveToHive(int score, int total, int erreurs, double moyenne) async {
    if (statsBox == null) return;

    final Map<String, dynamic> statEntry = {
      'matiere': widget.matiere,
      'sectionId': widget.sectionId,
      'score_questions': score, 
      'total_tentatives': total, 
      'erreurs': erreurs,
      'date': DateTime.now().toIso8601String(),
      'moyenne': moyenne,
      'pendingSync': true,
      'type': 'HTML_EXERCICE' // Utile pour différencier des quiz JSON
    };

    await statsBox!.put(widget.sectionId, statEntry);
  }

  void _showResultDialog(int score, int total, int erreurs, double moyenne) {
    String message;
    if (erreurs == 0) {
      message = "🟢 Ho le génie, félicitations !\nTu as tout cassé, bravo champion !";
    } else if (erreurs <= 2) {
      message = "🟢 Excellent, tu es un génie. Tu travailles trop propre. Chapeau !";
    } else if (erreurs <= 5) {
      message = "🟡 Bravo, tu as capté la leçon bien même. Tu es sur la bonne route. Continue seulement !";
    } else if (erreurs <= 8) {
      message = "🟡 Le niveau est là, mais faut pas dormir ! Resserre un peu les boulons et tu vas voler haut !";
    } else if (erreurs <= 10) {
      message = "🟠 Résultat passable mais tu peux faire mieux. Beaucoup de courage !";
    } else if (erreurs <= 13) {
      message = "🟠 « Yako boss ! Tu as pris quelques coups, mais l’essentiel c’est de pas lâcher. Courage, on est ensemble !";
    } else {
      message = "🔴 Faut pas djô, faut rester ici ! Reprends les cours là doucement. Tu vas revenir plus chaud que braise !";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("${widget.matiere} — Résultats"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Succès : $score / $total", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            Text("Erreurs : $erreurs", style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Text("Moyenne : ${moyenne.toStringAsFixed(2)} / 20", 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C00),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Regarde maintenant tes erreurs marquées en rouge sur la page."),
                  backgroundColor: Colors.blueGrey,
                ),
              );
            },
            child: const Text("VOIR MES ERREURS", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text("QUITTER", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.matiere),
        backgroundColor: const Color(0xFFFF8C00),
        elevation: 0,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}