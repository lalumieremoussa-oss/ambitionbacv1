// 📁 lib/tv_leaders/lecon_content_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../accueil/app_shared.dart';

// =====================================================================
// CONSTANTES
// =====================================================================
const String _r2BaseUrl = 'https://pub-a6d2205920ac4bee9cce64d6ab17bff0.r2.dev';

// =====================================================================
// SERVICE DE CACHE HIVE POUR LES LEÇONS
// =====================================================================

class LeconCacheService {
  static const String _boxName = 'lecon_cache';
  static Box? _box;

  static Future<Box> _getBox() async {
    _box ??= await Hive.openBox(_boxName);
    return _box!;
  }

  static Future<void> sauvegarderContenu(
      String leconId, String jsonString) async {
    final box = await _getBox();
    await box.put('${leconId}_json', jsonString);
  }

  static String? getContenu(String leconId) {
    final box = _box;
    if (box == null) return null;
    return box.get('${leconId}_json') as String?;
  }

  static Future<void> sauvegarderTitre(String leconId, String titre) async {
    final box = await _getBox();
    await box.put('${leconId}_titre', titre);
  }

  static String? getTitre(String leconId) {
    final box = _box;
    if (box == null) return null;
    return box.get('${leconId}_titre') as String?;
  }
}

// =====================================================================
// PAGE PRINCIPALE : CONTENU D'UNE LEÇON
// =====================================================================

class LeconContentPage extends StatefulWidget {
  final String leconId;
  final String leconTitre;
  final String chapterTitre;
  final String type; // 'LEAD' ou 'ENTREP'
  final TabUpdateCallback onUpdate;

  const LeconContentPage({
    super.key,
    required this.leconId,
    required this.leconTitre,
    required this.chapterTitre,
    required this.type,
    required this.onUpdate,
  });

  @override
  State<LeconContentPage> createState() => _LeconContentPageState();
}

class _LeconContentPageState extends State<LeconContentPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _data;
  List<dynamic> _parties = [];

  @override
  void initState() {
    super.initState();
    _loadContent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUpdate(
        title: widget.leconTitre,
        onBack: () {
          Navigator.pop(context);
          widget.onUpdate(
              title: widget.chapterTitre, onBack: () => Navigator.pop(context));
        },
      );
    });
  }

  Future<void> _loadContent() async {
    setState(() => _isLoading = true);

    try {
      // 1. Vérifier le cache Hive
      String? cachedJson = LeconCacheService.getContenu(widget.leconId);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson);
          setState(() {
            _data = decoded;
            _parties = decoded['parties'] ?? [];
            _isLoading = false;
          });
          return;
        } catch (e) {
          // Cache corrompu, on le supprime
          await LeconCacheService.sauvegarderContenu(widget.leconId, '');
        }
      }

      // 2. Télécharger depuis Cloudflare R2 via HTTP public
      final objectKey = '${widget.type.toLowerCase()}/${widget.leconId}.json';
      final url = '$_r2BaseUrl/leaders/$objectKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        await LeconCacheService.sauvegarderContenu(widget.leconId, jsonString);

        final jsonData = jsonDecode(jsonString);
        final titre = jsonData['titre'] ?? 'Sans titre';
        await LeconCacheService.sauvegarderTitre(widget.leconId, titre);

        setState(() {
          _data = jsonData;
          _parties = jsonData['parties'] ?? [];
          _isLoading = false;
        });
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _data = null;
      });
      _showErrorDialog(
          'Impossible de charger le contenu. Vérifiez votre connexion.\n$e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erreur'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.leconTitre),
        backgroundColor: kMatiereGreen,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
            widget.onUpdate(
                title: widget.chapterTitre,
                onBack: () => Navigator.pop(context));
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kAppOrange))
          : _data == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun contenu disponible pour cette leçon.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadContent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAppOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_data!['titre'] != null)
                        Text(
                          _data!['titre'],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: kAppOrange,
                          ),
                        ),
                      const SizedBox(height: 16),
                      ..._parties
                          .map((partie) => _buildPartie(partie))
                          .toList(),
                    ],
                  ),
                ),
    );
  }

  // ---- Construction des parties ----
  Widget _buildPartie(Map<String, dynamic> partie) {
    final titrePartie = partie['titre'] ?? 'Partie';
    final contenu = partie['contenu'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titrePartie,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: kAppOrange,
          ),
        ),
        const SizedBox(height: 8),
        ...contenu.map((element) => _buildElement(element)).toList(),
        const Divider(height: 32, thickness: 1.5, color: Colors.grey),
      ],
    );
  }

  Widget _buildElement(Map<String, dynamic> element) {
    final type = element['type'] as String? ?? '';
    final valeur = element['valeur'] ?? '';

    switch (type) {
      case 'titre':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            valeur,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        );
      case 'paragraphe':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            valeur,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        );
      case 'image':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CachedNetworkImage(
            imageUrl: valeur,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(color: kAppOrange),
            ),
            errorWidget: (context, url, error) =>
                const Icon(Icons.broken_image, size: 50),
            fit: BoxFit.contain,
          ),
        );
      case 'video':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: VideoPlayerWidget(videoUrl: valeur),
        );
      case 'audio':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AudioPlayerWidget(audioUrl: valeur),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// =====================================================================
// WIDGET VIDÉO
// =====================================================================

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const VideoPlayerWidget({super.key, required this.videoUrl});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        height: 200,
        color: Colors.black12,
        child:
            const Center(child: CircularProgressIndicator(color: kAppOrange)),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            children: [
              VideoPlayer(_controller),
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                      _isPlaying = !_isPlaying;
                    });
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            if (_isPlaying) {
                              _controller.pause();
                            } else {
                              _controller.play();
                            }
                            _isPlaying = !_isPlaying;
                          });
                        },
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: kAppOrange,
                            backgroundColor: Colors.grey,
                            bufferedColor: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen, color: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullScreenVideoPage(
                                controller: _controller,
                                videoUrl: widget.videoUrl,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 40,
                right: 8,
                child: Text(
                  '${_controller.value.position.inSeconds ~/ 60}:${(_controller.value.position.inSeconds % 60).toString().padLeft(2, '0')} / ${_controller.value.duration.inSeconds ~/ 60}:${(_controller.value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class FullScreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String videoUrl;
  const FullScreenVideoPage({
    super.key,
    required this.controller,
    required this.videoUrl,
  });

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _isInitialized = _controller.value.isInitialized;
    _isPlaying = _controller.value.isPlaying;
    _controller.addListener(() {
      setState(() => _isPlaying = _controller.value.isPlaying);
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.removeListener(() {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: kAppOrange,
                        backgroundColor: Colors.grey,
                        bufferedColor: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10,
                              color: Colors.white, size: 30),
                          onPressed: () {
                            final newPos = _controller.value.position -
                                const Duration(seconds: 10);
                            _controller.seekTo(newPos < Duration.zero
                                ? Duration.zero
                                : newPos);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 40,
                          ),
                          onPressed: () {
                            if (_isPlaying) {
                              _controller.pause();
                            } else {
                              _controller.play();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10,
                              color: Colors.white, size: 30),
                          onPressed: () {
                            final newPos = _controller.value.position +
                                const Duration(seconds: 10);
                            _controller.seekTo(
                              newPos > _controller.value.duration
                                  ? _controller.value.duration
                                  : newPos,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_controller.value.position.inSeconds ~/ 60}:${(_controller.value.position.inSeconds % 60).toString().padLeft(2, '0')} / ${_controller.value.duration.inSeconds ~/ 60}:${(_controller.value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// WIDGET AUDIO
// =====================================================================

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  const AudioPlayerWidget({super.key, required this.audioUrl});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) => setState(() => _duration = d));
    _player.onPositionChanged.listen((p) => setState(() => _position = p));
    _player.onPlayerComplete.listen((_) => setState(() => _isPlaying = false));
    // Précharger l'audio
    _player.play(UrlSource(widget.audioUrl));
    _player.pause();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: kAppOrange,
              ),
              onPressed: () {
                if (_isPlaying) {
                  _player.pause();
                } else {
                  _player.play(UrlSource(widget.audioUrl));
                }
                setState(() => _isPlaying = !_isPlaying);
              },
            ),
            Expanded(
              child: Column(
                children: [
                  Slider(
                    value: _position.inSeconds.toDouble(),
                    min: 0,
                    max: _duration.inSeconds.toDouble(),
                    onChanged: (val) {
                      final newPos = Duration(seconds: val.toInt());
                      _player.seek(newPos);
                    },
                    activeColor: kAppOrange,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_position.inSeconds ~/ 60}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${_duration.inSeconds ~/ 60}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
