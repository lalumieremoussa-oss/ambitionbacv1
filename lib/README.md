# Coach vocal IA — 100% AUDIO → AUDIO natif (Gemini Live)

## Ce qui a changé par rapport à la version précédente

**Avant** : micro → audio envoyé à `generateContent` → Gemini répondait en
**texte** → `flutter_tts` transformait ce texte en voix localement.
C'est cette conversion texte → voix que tu ne voulais plus.

**Maintenant** : micro → audio envoyé à l'Edge Function → l'Edge Function
ouvre une connexion **Gemini Live** (`gemini-3.1-flash-live-preview`, le
modèle à audio natif) → Gemini écoute l'audio ET génère directement sa
propre voix en réponse → l'Edge Function renvoie ce fichier audio tel quel
→ Flutter le joue avec `audioplayers`.

**❌ Plus de `flutter_tts` nulle part. ❌ Plus de conversion texte → voix.**
Le seul texte qui existe encore est une **transcription optionnelle**
(activée pour l'affichage "Afficher le texte" dans les bulles), mais elle
n'est **jamais** réinjectée dans un moteur de synthèse : la voix qui sort du
téléphone est à 100% celle générée nativement par Gemini.

## Pourquoi une Edge Function fait le pont WebSocket

L'API "audio natif" de Gemini (Gemini Live) fonctionne uniquement en
**WebSocket** (protocole `BidiGenerateContent`), pas en simple requête HTTP.
Flutter, lui, doit rester simple et ne jamais connaître la clé API. La
solution :

```
Flutter --(HTTP POST classique, comme avant)--> Edge Function Supabase
Edge Function --(WebSocket, le temps d'UN SEUL tour)--> Gemini Live
Edge Function <--(audio généré par Gemini)-- Gemini Live
Flutter <--(HTTP 200, fichier WAV)-- Edge Function
```

Le WebSocket n'existe que côté serveur, pendant quelques secondes, pour un
seul échange — exactement le fonctionnement "tour par tour" que tu voulais
(pas de session vocale permanente).

## Format audio (important, ne pas modifier)

- **Entrée** (élève → Gemini) : PCM 16 bits, mono, **16 000 Hz**, brut (sans
  entête WAV) — Flutter extrait ce flux brut du fichier `.wav` enregistré
  par le package `record` avant de l'envoyer.
- **Sortie** (Gemini → élève) : PCM 16 bits, mono, **24 000 Hz** — l'Edge
  Function l'enveloppe dans un conteneur WAV valide avant de le renvoyer, ce
  qui le rend directement lisible par `audioplayers`.

## Fichiers livrés

```
lib/ia_pages/gemini_service.dart   → client HTTP (envoie du PCM, reçoit un WAV)
lib/ia_pages/ia_an_coach.dart      → écran coach Anglais (100% audio natif)
lib/ia_pages/ia_lv2_coach.dart     → écran coach Allemand/Espagnol (idem)
lib/tabs/ambition_ia_tab.dart      → inchangé
supabase/functions/coach-ai/index.ts → pont WebSocket vers Gemini Live
supabase/sql/coach_setup.sql       → tables + RPC de crédit (inchangé)
assets/iac/ANG2.txt, DE.txt, ES.txt → prompts système des coachs
```

## Étapes de mise en place

### 1. Base de données Supabase
Si ce n'est pas déjà fait, exécute `supabase/sql/coach_setup.sql` dans le
SQL Editor (tables `utilisateurs_premium.premium` / `.minutecoach` + RPC
`consume_coach_seconds`). La table `coach_config` n'est plus utilisée par
cette version audio-native (elle ne gênera pas si elle existe déjà).

### 2. Clé API Gemini
```bash
supabase secrets set GEMINI_API_KEY=ta_cle_ici
```
Optionnel :
```bash
supabase secrets set COACH_LIVE_MODEL=gemini-3.1-flash-live-preview
supabase secrets set COACH_FREE_SECONDS=300
supabase secrets set COACH_PREMIUM_SECONDS=3000
```

### 3. Déployer l'Edge Function
```bash
supabase functions deploy coach-ai
```

### 4. Dépendances Flutter (`pubspec.yaml`)
```yaml
dependencies:
  http: ^1.2.0
  supabase_flutter: ^2.5.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  path_provider: ^2.1.3
  record: ^6.1.1
  audioplayers: ^6.1.0
  shared_preferences: ^2.2.3
  # ❌ flutter_tts n'est PLUS nécessaire — tu peux le retirer du pubspec.

flutter:
  assets:
    - assets/iac/ANG2.txt
    - assets/iac/DE.txt
    - assets/iac/ES.txt
```

### 5. Permissions natives (inchangées)
**Android** :
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```
**iOS** :
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Le microphone est nécessaire pour parler avec votre coach IA.</string>
```

## Déroulé d'un échange (comme un message vocal WhatsApp)

1. L'élève appuie sur le micro → enregistrement PCM16 16kHz local (`.wav`).
2. Il rappuie → aperçu (écoute/suppression possible) → "Envoyer".
3. Flutter extrait le PCM brut du `.wav`, l'encode en base64, l'envoie à
   `coach-ai` avec le matricule et le prompt système.
4. L'Edge Function vérifie le crédit, ouvre un WebSocket vers Gemini Live,
   envoie l'audio par paquets de ~250ms puis signale la fin (`audioStreamEnd`).
5. Gemini écoute, raisonne et **génère directement sa voix** (PCM 24kHz) —
   aucune étape texte entre l'écoute et la génération vocale.
6. L'Edge Function assemble l'audio reçu, l'enveloppe en WAV, décrémente le
   crédit, et répond à Flutter en HTTP.
7. Flutter écrit le WAV sur disque, le joue **automatiquement** avec
   `audioplayers`, et le garde en local (Hive + fichier) pour une relecture
   possible même après avoir quitté puis rouvert l'application.

## Mémoire de conversation (sans jamais repasser par un TTS)

Pour que le coach garde le fil d'un message à l'autre sans devoir renvoyer
tous les audios précédents à chaque tour, l'app conserve une **petite
mémoire textuelle** (les transcriptions optionnelles des échanges récents)
et l'ajoute au prompt système du tour suivant, uniquement comme rappel de
contexte. Cette mémoire n'est **jamais** transformée en audio localement —
seul Gemini génère de la voix, à chaque tour, à partir de l'audio du
nouveau message de l'élève.

## Limites et points d'attention

- **`gemini-3.1-flash-live-preview` est un modèle "preview"** : son nom ou
  ses quotas peuvent changer côté Google. Si l'appel échoue avec une erreur
  de modèle inconnu, vérifie le nom exact sur
  https://ai.google.dev/gemini-api/docs/live-api/capabilities.
- **Latence** : elle dépend du réseau et de la longueur de l'audio envoyé.
  L'objectif de <5s est réaliste pour des messages courts (5-15s) avec une
  bonne connexion, mais n'est pas garanti par Google.
- **`record` + `AudioEncoder.pcm16bits`** : sur certains appareils/anciennes
  versions du plugin, le fichier produit peut ne pas être un WAV valide
  (variations selon plateforme). Le code extrait le PCM en cherchant le
  sous-bloc `data` du WAV plutôt que de supposer un décalage fixe de 44
  octets — si jamais le fichier généré est déjà du PCM brut sans entête,
  `extractPcmFromWav` le détecte et le renvoie tel quel. Teste sur un
  appareil réel avant mise en production.
- Le nom des voix Gemini (`Kore`, `Puck`, etc.) peut évoluer ; vérifie la
  liste à jour dans la doc "speech generation" de Google si tu veux changer
  les voix des professeurs.
