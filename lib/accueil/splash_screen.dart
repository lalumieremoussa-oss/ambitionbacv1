import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'home_page.dart';

// ==================== SPLASH SCREEN SANS EXPIRATION ====================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _logoOpacityAnimation;
  late Animation<double> _sloganOpacityAnimation;
  late Animation<double> _sloganSlideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 4 * math.pi).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOutBack),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.2, end: 4.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _logoOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _sloganOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 0.9, curve: Curves.easeIn),
      ),
    );

    _sloganSlideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 0.9, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
    _navigateAfterDelay();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Navigation après l'animation (4,2 secondes)
  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 4200));

    // Récupération des préférences pour savoir si l'utilisateur est déjà enregistré
    final prefs = await SharedPreferences.getInstance();
    final String? userName = prefs.getString('nom');
    final String? matricule = prefs.getString('matricule');

    if (!mounted) return;

    Widget nextStep = (userName != null || matricule != null)
        ? const HomePage()
        : const WelcomePage();

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextStep,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _logoOpacityAnimation.value,
                  child: Transform.rotate(
                    angle: _rotationAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Image.asset(
                        'assets/images/outils/ambitionplus.png',
                        width: 150,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _sloganOpacityAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _sloganSlideAnimation.value),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "AMBITION +",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF8C00),
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xFFFF8C00), width: 1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "VOTRE RACCOURCI VERS LA RÉUSSITE",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontStyle: FontStyle.italic,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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
