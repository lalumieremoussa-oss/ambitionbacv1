// 📁 lib/accueil/welcome_page.dart

import 'package:flutter/material.dart';
import '../login/login_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🟠 1️⃣ Bandeau supérieur
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 40, bottom: 60),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF8C00),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                  child: Column(
                    children: const [
                      Text(
                        "AMBITION + BAC",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 26,
                          letterSpacing: 1.5,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "VOTRE RACCOURCI VERS LA RÉUSSITE",
                        style: TextStyle(
                          color: Colors.white,
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: -45,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          'assets/images/outils/logo_ambitionbac.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 70),

            // 🧩 Zone 1
            _buildSection(
              title: "Présentation générale",
              text:
                  "Ambition+ Bac est une plateforme éducative ivoirienne conçue pour propulser les élèves de terminale vers l'excellence. "
                  "Elle allie formation théorique rigoureuse et compétences pratiques, avec une approche innovante et accessible à tous.",
              imagePath: 'assets/images/outils/section1.png',
              imageLeft: true,
            ),

            // 🧩 Zone 2
            _buildSection(
              title: "Cours, exercices et quiz interactifs",
              text:
                  "Des cours clairs et structurés, des exercices corrigés pas à pas, et des quiz ludiques pour valider vos acquis. "
                  "Entraînez-vous efficacement et suivez votre progression en temps réel.",
              imagePath: 'assets/images/outils/section2.png',
              imageLeft: false,
            ),

            // 🧩 Zone 3
            _buildSection(
              title: "Vidéos pédagogiques et laboratoires virtuels",
              text:
                  "Accédez à des vidéos qui illustrent les démonstrations mathématiques, les mécanismes biologiques, "
                  "les expériences de physique-chimie, et des laboratoires virtuels immersifs pour une compréhension profonde.",
              imagePath: 'assets/images/outils/section3.png',
              imageLeft: true,
            ),

            // 🧩 Zone 4
            _buildSection(
              title: "Intelligence Artificielle ivoirienne",
              text:
                  "Nos IA spécialement entraînées vous guident dans la méthodologie et le raisonnement, conformément aux exigences du système éducatif ivoirien. "
                  "Dissertations, commentaires et analyses sont 100% conformes aux méthodologies ivoiriens.",
              imagePath: 'assets/images/outils/section4.png',
              imageLeft: false,
            ),

            // 🧩 Zone 5
            _buildSection(
              title: "Actualités éducatives, entrepreneuriat & leadership",
              text:
                  "Suivez une chaîne vidéo dédiée à l'actualité éducative, et plongez dans un espace de formation au leadership et à l'entrepreneuriat. "
                  "Développez une mentalité de bâtisseur, avec des contenus motivants et des ouvertures sur le monde professionnel.",
              imagePath: 'assets/images/outils/section5.png',
              imageLeft: true,
            ),

            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginPage()),
                    );
                  },
                  child: const Text(
                    "COMMENCER",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Widget utilitaire pour chaque section
  Widget _buildSection({
    required String title,
    required String text,
    required String imagePath,
    required bool imageLeft,
  }) {
    final imageWidget = Expanded(
      flex: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Image.asset(imagePath, fit: BoxFit.contain),
      ),
    );

    final textWidget = Expanded(
      flex: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment:
              imageLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: imageLeft ? TextAlign.right : TextAlign.left,
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: imageLeft ? TextAlign.right : TextAlign.left,
            ),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFB6FFB6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:
            imageLeft ? [imageWidget, textWidget] : [textWidget, imageWidget],
      ),
    );
  }
}
