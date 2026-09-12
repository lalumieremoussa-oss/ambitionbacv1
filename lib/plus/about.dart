import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _ivoryCoastOrange = Color(0xFFFF8C00);
const Color _ivoryCoastGreen = Color(0xFF009C4A);
const Color _lightBackground = Color(0xFFF4F7F6);

class AboutAmbitionPage extends StatefulWidget {
  const AboutAmbitionPage({super.key});

  @override
  State<AboutAmbitionPage> createState() => _AboutAmbitionPageState();
}

class _AboutAmbitionPageState extends State<AboutAmbitionPage>
    with TickerProviderStateMixin {
  final PageController _heroController = PageController();
  final PageController _contentController = PageController();

  Timer? _heroTimer;

  int _heroIndex = 0;
  int _contentIndex = 0;

  late AnimationController _textAnimationController;

  final List<_HeroSlide> _heroSlides = [
    _HeroSlide(
      image: 'assets/images/outils/slide1.png',
      lines: [
        "L’ÈRE DE LA RÉVOLUTION ÉDUCATIVE A COMMENCÉ.",
        "AMBITION+ POUR CRÉER LES BÂTISSEURS DE DEMAIN.",
        "ENSEMBLE, BÂTISSONS UNE CÔTE D’IVOIRE PLUS FORTE ET PLUS DÉVELOPPÉE. 🇨🇮",
      ],
    ),
    _HeroSlide(
      image: 'assets/images/outils/slide2.png',
      lines: [
        "À BAS LA MÉDIOCRITÉ !",
        "À BAS LA RÉSIGNATION !",
        "À BAS LES LIMITES !",
      ],
    ),
    _HeroSlide(
      image: 'assets/images/outils/slide3.png',
      lines: [
        "PLACE À L’EXCELLENCE.",
        "PLACE À L’AMBITION.",
        "PLACE AUX BÂTISSEURS.",
      ],
    ),
    _HeroSlide(
      image: 'assets/images/outils/slide4.png',
      lines: [
        "AMBITION+ — L’ÉDUCATION QUI PRÉPARE À BÂTIR L’AVENIR.",
        "AMBITION+ — VOTRE RACCOURCI VERS LA RÉUSSITE.",
        "UNE NOUVELLE GÉNÉRATION SE PRÉPARE.",
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();

    _textAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _startHeroAnimation();

    _heroTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (!mounted) return;

        final next = (_heroIndex + 1) % _heroSlides.length;

        _heroController.animateToPage(
          next,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      },
    );
  }

  void _startHeroAnimation() {
    _textAnimationController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    _contentController.dispose();
    _textAnimationController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);

    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception("Impossible d'ouvrir $url");
    }
  }

  Future<void> _shareApp() async {
    final ByteData data =
        await rootBundle.load('assets/images/outils/send.png');

    final Directory tempDir = await getTemporaryDirectory();
    final File file = File('${tempDir.path}/send.png');

    await file.writeAsBytes(data.buffer.asUint8List());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: '🚀 AMBITION+ BAC\n\n'
          'L’application éducative ivoirienne qui accompagne les élèves '
          'vers l’excellence et prépare les bâtisseurs de demain. 🇨🇮\n\n'
          '📝 Cours clairs et structurés\n'
          '💡 Exercices et quiz interactifs\n'
          '🎯 Anciens sujets et corrigés\n'
          '🎥 Vidéos pédagogiques\n'
          '🤖 Intelligence artificielle éducative, 100% contexte ivoirien\n'
          '🏆 Progression et challenges\n'
          '🚀 Entrepreneuriat & leadership\n\n'
          '👉 Télécharge dès maintenant : '
          'https://ivoire.pages.dev/apps',
      subject: '🚀 AMBITION+ BAC',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: _lightBackground,
      appBar: AppBar(
        title: const Text(
          "À PROPOS D'AMBITION+",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        centerTitle: true,
        backgroundColor: _ivoryCoastOrange,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.share,
              color: Colors.white,
            ),
            onPressed: _shareApp,
          ),
        ],
      ),
      body: Column(
        children: [
          // ==========================================================
          // 🎬 BANDEAU CINÉMATIQUE — 40% DE L'ÉCRAN
          // ==========================================================

          SizedBox(
            height: screenHeight * 0.40,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _heroController,
                  itemCount: _heroSlides.length,
                  onPageChanged: (index) {
                    setState(() {
                      _heroIndex = index;
                    });

                    _startHeroAnimation();
                  },
                  itemBuilder: (context, index) {
                    return _buildHeroSlide(
                      _heroSlides[index],
                    );
                  },
                ),

                // Dégradé inférieur
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Indicateurs
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _heroSlides.length,
                      (index) {
                        final selected = index == _heroIndex;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: selected ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: selected
                                ? _ivoryCoastOrange
                                : Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ==========================================================
          // 📚 CONTENU — UNE PARTIE À LA FOIS
          // ==========================================================

          Expanded(
            child: PageView.builder(
              controller: _contentController,
              itemCount: 6,
              onPageChanged: (index) {
                setState(() {
                  _contentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                switch (index) {
                  case 0:
                    return _buildPresentationPage();

                  case 1:
                    return _buildCoursesPage();

                  case 2:
                    return _buildVideosPage();

                  case 3:
                    return _buildBatisseursPage();

                  case 4:
                    return _buildConclusionPage();

                  case 5:
                    return _buildOtherAppsPage();

                  default:
                    return const SizedBox();
                }
              },
            ),
          ),

          // ==========================================================
          // 🔘 INDICATEUR DE PROGRESSION
          // ==========================================================

          Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: 8,
            ),
            child: Row(
              children: [
                Text(
                  "${_contentIndex + 1}/6",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: (_contentIndex + 1) / 6,
                      backgroundColor: Colors.black12,
                      valueColor:
                          const AlwaysStoppedAnimation(_ivoryCoastOrange),
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

  // ================================================================
  // 🎬 HERO SLIDE
  // ================================================================

  Widget _buildHeroSlide(_HeroSlide slide) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          slide.image,
          fit: BoxFit.cover,
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.15),
                Colors.black.withOpacity(0.72),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 25,
          ),
          child: AnimatedBuilder(
            animation: _textAnimationController,
            builder: (context, child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  slide.lines.length,
                  (index) {
                    final start = index * 0.25;
                    final end = start + 0.45;

                    final animation = CurvedAnimation(
                      parent: _textAnimationController,
                      curve: Interval(
                        start.clamp(0.0, 1.0),
                        end.clamp(0.0, 1.0),
                        curve: Curves.easeOutCubic,
                      ),
                    );

                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.35),
                          end: Offset.zero,
                        ).animate(animation),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            slide.lines[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: index == 0 ? 17 : 14,
                              fontWeight: index == 0
                                  ? FontWeight.w900
                                  : FontWeight.bold,
                              height: 1.25,
                              letterSpacing: 0.4,
                              shadows: const [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ================================================================
  // 🧩 STRUCTURE COMMUNE DES PAGES
  // ================================================================

  Widget _contentPage({
    required String number,
    required String title,
    required String description,
    required String imagePath,
    required List<String> points,
  }) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _ivoryCoastOrange,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  "PARTIE $number",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: Colors.black12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 155,
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: 15),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF202426),
              height: 1.15,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Colors.grey[700],
            ),
          ),

          const SizedBox(height: 16),

          ...points.map(
            (point) => Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: _ivoryCoastOrange.withOpacity(0.10),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: _ivoryCoastGreen,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
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

  // ================================================================
  // 1️⃣ PRÉSENTATION
  // ================================================================

  Widget _buildPresentationPage() {
    return _contentPage(
      number: "1",
      title: "UNE NOUVELLE FAÇON D’APPRENDRE",
      description:
          "AMBITION+ BAC est une plateforme éducative ivoirienne pensée pour accompagner les élèves vers l’excellence. "
          "Notre objectif est simple : rendre l’apprentissage plus clair, plus accessible, plus vivant et surtout plus efficace.",
      imagePath: 'assets/images/outils/learning.png',
      points: [
        "Des contenus structurés selon les exigences du système éducatif ivoirien.",
        "Une pédagogie qui transforme les notions difficiles en connaissances réellement compréhensibles.",
        "Un accompagnement conçu pour aider chaque apprenant à progresser à son propre rythme.",
        "Une préparation au BAC qui associe connaissances, méthode, discipline et confiance en soi.",
      ],
    );
  }

  // ================================================================
  // 2️⃣ COURS / EXERCICES / QUIZ
  // ================================================================

  Widget _buildCoursesPage() {
    return _contentPage(
      number: "2",
      title: "APPRENDRE, S’ENTRAÎNER, PROGRESSER",
      description:
          "La réussite ne repose pas uniquement sur la mémorisation. Elle se construit par la compréhension, la répétition et l’entraînement. "
          "AMBITION+ rassemble les outils essentiels pour transformer chaque séance de travail en véritable progression.",
      imagePath: 'assets/images/outils/cours.png',
      points: [
        "Des cours clairs, structurés et faciles à consulter.",
        "Des exercices d’entraînement accompagnés de corrigés pédagogiques.",
        "Des anciens sujets pour se confronter aux véritables exigences des examens.",
        "Des quiz interactifs pour tester rapidement ses connaissances.",
        "Des mécanismes de progression pour transformer l’entraînement en motivation.",
      ],
    );
  }

  // ================================================================
  // 3️⃣ VIDÉOS / LABORATOIRES
  // ================================================================

  Widget _buildVideosPage() {
    return _contentPage(
      number: "3",
      title: "VOIR POUR COMPRENDRE",
      description:
          "Certaines notions sont difficiles à comprendre lorsqu’elles restent uniquement dans un livre. "
          "AMBITION+ utilise la vidéo, les démonstrations et les expériences virtuelles pour rendre les connaissances concrètes.",
      imagePath: 'assets/images/outils/exo.png',
      points: [
        "Des démonstrations mathématiques expliquées étape par étape.",
        "Des phénomènes scientifiques rendus visibles et compréhensibles.",
        "Des expériences de physique-chimie présentées de manière immersive.",
        "Des mécanismes biologiques expliqués avec des supports visuels.",
        "Des contenus pédagogiques conçus pour apprendre autrement et retenir durablement.",
      ],
    );
  }

  // ================================================================
  // 4️⃣ IA + ENTREPRENEURIAT + LEADERSHIP
  // ================================================================

  Widget _buildBatisseursPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        children: [
          _partBadge("PARTIE 4"),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/outils/home_bg.png',
              height: 170,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "FORMER DES BÂTISSEURS, PAS SEULEMENT DES DIPLÔMÉS",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "L’éducation ne doit pas s’arrêter à l’obtention d’un diplôme. "
            "Nous voulons contribuer à former une génération capable de réfléchir, "
            "d’entreprendre, d’innover, de diriger et de créer de la valeur.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 18),
          _buildBatisseurItem(
            Icons.smart_toy_rounded,
            "INTELLIGENCE ARTIFICIELLE",
            "Une IA éducative spécialisée pour accompagner l’apprenant dans son raisonnement, "
                "ses méthodologies et sa compréhension des notions.",
          ),
          _buildBatisseurItem(
            Icons.rocket_launch_rounded,
            "ENTREPRENEURIAT",
            "Développer l’esprit d’initiative, apprendre à transformer une idée en projet "
                "et découvrir les réalités du monde professionnel.",
          ),
          _buildBatisseurItem(
            Icons.groups_rounded,
            "LEADERSHIP",
            "Apprendre à prendre des responsabilités, travailler en équipe, résoudre des problèmes "
                "et devenir un acteur du développement de sa communauté.",
          ),
          _buildBatisseurItem(
            Icons.public_rounded,
            "OUVERTURE SUR LE MONDE",
            "Une éducation qui prépare les jeunes à comprendre leur environnement, "
                "à saisir les opportunités et à participer activement au développement de la Côte d’Ivoire.",
          ),
        ],
      ),
    );
  }

  // ================================================================
  // 🏆 CONCLUSION
  // ================================================================

  Widget _buildConclusionPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        children: [
          _partBadge("CONCLUSION"),

          const SizedBox(height: 15),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _ivoryCoastOrange.withOpacity(0.12),
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: _ivoryCoastOrange.withOpacity(0.20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 220,
                  height: 90,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/outils/suiteambition.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "CE N’EST QUE LE COMMENCEMENT.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _ivoryCoastOrange,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Ce que vous voyez aujourd’hui n’est que 10 % de notre vision.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "L’ÈRE DE LA RÉVOLUTION ÉDUCATIVE A COMMENCÉ.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "AMBITION+ POUR CRÉER LES BÂTISSEURS DE DEMAIN.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.bold,
                    color: _ivoryCoastGreen,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "ENSEMBLE, BÂTISSONS UNE CÔTE D’IVOIRE PLUS FORTE ET PLUS DÉVELOPPÉE. 🇨🇮",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  "À BAS LA MÉDIOCRITÉ !",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ivoryCoastOrange,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "PLACE À L’EXCELLENCE.\n"
                  "PLACE À L’AMBITION.\n"
                  "PLACE AUX BÂTISSEURS.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ========================================================
          // 🌐 ACTIONS
          // ========================================================

          Row(
            children: [
              Expanded(
                child: _smallActionButton(
                  label: "SITE WEB",
                  icon: Icons.language,
                  color: _ivoryCoastOrange,
                  onTap: () => _launchUrl(
                    'https://ivoire.pages.dev',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _smallActionButton(
                  label: "PARTAGER",
                  icon: Icons.share_rounded,
                  color: _ivoryCoastGreen,
                  onTap: _shareApp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================================
  // 📱 NOS AUTRES APPLICATIONS
  // ================================================================

  Widget _buildOtherAppsPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        children: [
          _partBadge("NOS AUTRES APPLICATIONS"),
          const SizedBox(height: 10),
          const Text(
            "L’ÉCOSYSTÈME AMBITION+",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Une ambition : accompagner l’apprenant tout au long de son parcours scolaire et professionnel.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          _otherAppCard(
            title: "AMBITION+ COLLÈGE",
            subtitle: "De la 6ème à la 4ème",
            description:
                "Cours, exercices et accompagnement pour renforcer les bases et préparer efficacement la suite du parcours scolaire.",
            imagePath: 'assets/images/outils/logo_ambitioncollege.png',
            color: Colors.blue.shade700,
          ),
          _otherAppCard(
            title: "AMBITION+ BEPC",
            subtitle: "Préparation au BEPC",
            description:
                "Cours, exercices, sujets et entraînements pour préparer efficacement le BEPC.",
            imagePath: 'assets/images/outils/logo_ambitionbepc.png',
            color: Colors.blue.shade700,
          ),
          _otherAppCard(
            title: "AMBITION+ LYCÉE",
            subtitle: "Seconde et Première",
            description:
                "Un accompagnement adapté aux classes de Seconde et Première pour construire progressivement la réussite au lycée.",
            imagePath: 'assets/images/outils/logo_ambitionlycee.png',
            color: _ivoryCoastOrange,
          ),
          _otherAppCard(
            title: "AMBITION+ CONCOURS",
            subtitle: "Concours en Côte d’Ivoire",
            description:
                "Informations, cours, anciens sujets et corrigés pour accompagner les candidats aux concours.",
            imagePath: 'assets/images/outils/logo_ambitionconcours.png',
            color: _ivoryCoastGreen,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: _ivoryCoastOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.open_in_new,
                  color: _ivoryCoastOrange,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Découvrez toutes nos solutions sur notre plateforme.",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          _smallActionButton(
            label: "DÉCOUVRIR NOS APPLICATIONS",
            icon: Icons.apps_rounded,
            color: _ivoryCoastOrange,
            onTap: () => _launchUrl(
              'https://ivoire.pages.dev/apps',
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // 🔘 BADGE PARTIE
  // ================================================================

  Widget _partBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: _ivoryCoastOrange,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ================================================================
  // 🚀 BÂTISSEUR ITEM
  // ================================================================

  Widget _buildBatisseurItem(
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: _ivoryCoastGreen.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: _ivoryCoastGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // 📱 CARTE AUTRE APPLICATION
  // ================================================================

  Widget _otherAppCard({
    required String title,
    required String subtitle,
    required String description,
    required String imagePath,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.18),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _launchUrl(
          'https://ivoire.pages.dev/apps',
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // 🔘 PETIT BOUTON
  // ================================================================

  Widget _smallActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 18,
        ),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// 🎬 MODÈLE HERO
// ================================================================

class _HeroSlide {
  final String image;
  final List<String> lines;

  const _HeroSlide({
    required this.image,
    required this.lines,
  });
}
