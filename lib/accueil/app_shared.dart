// 📁 lib/shared/app_shared.dart
//
// Éléments partagés entre HomePage (le Scaffold principal) et les 5 onglets.
// Isolés ici pour éviter les imports circulaires entre home_page.dart et
// les fichiers de lib/tabs/*.

import 'package:flutter/material.dart';

/// Couleur orange officielle de l'application.
const Color kAppOrange = Color(0xFFFF8C00);

/// Couleur verte utilisée pour les cartes "matières".
const Color kMatiereGreen = Color(0xFF156515);

/// Signature utilisée par chaque onglet pour signaler à [HomePage] que :
///  - son titre doit apparaître dans l'AppBar principale (si l'onglet est actif) ;
///  - un bouton retour doit (ou non) être affiché dans l'AppBar (navigation
///    interne à l'onglet : matière → leçon → section, calendrier complet, etc.).
///
/// Chaque onglet appelle ceci à chaque changement de "vue" interne. HomePage
/// ne met à jour l'AppBar que si l'onglet concerné est bien l'onglet actif.
typedef TabUpdateCallback = void Function({String? title, VoidCallback? onBack});