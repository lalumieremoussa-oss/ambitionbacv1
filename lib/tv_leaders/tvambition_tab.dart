// 📁 lib/tabs/tvambition_tab.dart
//
// Onglet "Ambition+ TV" – Lecteur vidéo complet avec miniatures, contrôles, likes et commentaires.
// Les métadonnées sont mises en cache dans Hive.
// Les miniatures sont générées à partir de la première image de chaque vidéo (package video_thumbnail).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../accueil/app_shared.dart';

// Clé de la box Hive pour le cache des vidéos TV
const String _kCacheBox = 'tv_cache';
const String _kCacheKey = 'videos';

/// Modèle représentant une vidéo TV.
class TvVideo {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String videoUrl;
  final DateTime createdAt;
  Uint8List? thumbnailBytes; // cache de la miniature

  TvVideo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.videoUrl,
    required this.createdAt,
    this.thumbnailBytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'videoUrl': videoUrl,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TvVideo.fromJson(Map<String, dynamic> json) => TvVideo(
        id: json['id'],
        title: json['title'],
        subtitle: json['subtitle'],
        description: json['description'],
        videoUrl: json['videoUrl'],
        createdAt: DateTime.parse(json['createdAt']),
      );

  factory TvVideo.fromSupabase(Map<String, dynamic> data) => TvVideo(
        id: data['id'],
        title: data['title'] ?? 'Sans titre',
        subtitle: data['subtitle'] ?? '',
        description: data['description'] ?? '',
        videoUrl: data['video_url'],
        createdAt: DateTime.parse(data['created_at']),
      );
}

/// Service pour gérer les vidéos TV (cache + Supabase).
class TvVideoService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_kCacheBox)) {
      return Hive.box(_kCacheBox);
    }
    return Hive.openBox(_kCacheBox);
  }

  static Future<List<TvVideo>> getVideos() async {
    try {
      final box = await _getBox();
      final cached = box.get(_kCacheKey);
      if (cached != null) {
        try {
          final List<dynamic> list = json.decode(cached);
          return list
              .map((e) => TvVideo.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          debugPrint('Erreur décodage cache TV : $e');
        }
      }
      final videos = await _fetchFromSupabase();
      if (videos.isNotEmpty) {
        final jsonStr = json.encode(videos.map((v) => v.toJson()).toList());
        await box.put(_kCacheKey, jsonStr);
      }
      return videos;
    } catch (e) {
      debugPrint('Erreur accès cache Hive : $e');
      return _fetchFromSupabase();
    }
  }

  static Future<List<TvVideo>> refreshVideos() async {
    final videos = await _fetchFromSupabase();
    if (videos.isNotEmpty) {
      try {
        final box = await _getBox();
        final jsonStr = json.encode(videos.map((v) => v.toJson()).toList());
        await box.put(_kCacheKey, jsonStr);
      } catch (e) {
        debugPrint('Erreur écriture cache TV : $e');
      }
    }
    return videos;
  }

  static Future<List<TvVideo>> _fetchFromSupabase() async {
    try {
      final response = await _supabase
          .from('videos_tv')
          .select('*')
          .order('created_at', ascending: false)
          .limit(5);
      return (response as List).map((e) => TvVideo.fromSupabase(e)).toList();
    } catch (e) {
      debugPrint('Erreur chargement vidéos Supabase : $e');
      return [];
    }
  }

  static Future<int> getLikesCount(String videoId) async {
    try {
      final response = await _supabase
          .from('tv_likes')
          .select('id')
          .eq('video_id', videoId)
          .count(CountOption.exact);
      return response.count;
    } catch (e) {
      return 0;
    }
  }

  static Future<bool> hasUserLiked(String videoId, String matricule) async {
    try {
      final result = await _supabase
          .from('tv_likes')
          .select('id')
          .eq('video_id', videoId)
          .eq('user_matricule', matricule)
          .maybeSingle();
      return result != null;
    } catch (e) {
      return false;
    }
  }

  static Future<void> toggleLike(String videoId, String matricule) async {
    final liked = await hasUserLiked(videoId, matricule);
    if (liked) {
      await _supabase
          .from('tv_likes')
          .delete()
          .eq('video_id', videoId)
          .eq('user_matricule', matricule);
    } else {
      await _supabase.from('tv_likes').insert({
        'video_id': videoId,
        'user_matricule': matricule,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> getComments(String videoId) async {
    try {
      final response = await _supabase
          .from('tv_commentaires')
          .select('*')
          .eq('video_id', videoId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  static Future<void> addComment({
    required String videoId,
    required String matricule,
    required String userName,
    required String commentaire,
  }) async {
    await _supabase.from('tv_commentaires').insert({
      'video_id': videoId,
      'user_matricule': matricule,
      'user_name': userName,
      'commentaire': commentaire,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

// ============================================================================
// Widget principal
// ============================================================================

class TvAmbitionTab extends StatefulWidget {
  const TvAmbitionTab({super.key});

  @override
  State<TvAmbitionTab> createState() => _TvAmbitionTabState();
}

class _TvAmbitionTabState extends State<TvAmbitionTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<TvVideo> _videos = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;

  // Vidéo en cours
  TvVideo? _currentVideo;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _videoError = false;

  // Contrôles
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // Likes / Commentaires
  int _likesCount = 0;
  bool _userLiked = false;
  String? _userMatricule;
  String? _userName;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = false;

  // Thumbnails générées
  final Map<String, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _initUserInfo();
    _loadVideos();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _userMatricule = prefs.getString('matricule') ?? 'unknown';
    
    // Récupération combinée du nom et du prénom
    final nom = prefs.getString('nom') ?? '';
    final prenom = prefs.getString('prenom') ?? '';
    final fullName = '$nom $prenom'.trim();
    
    _userName = fullName.isNotEmpty ? fullName : 'Élève';
    if (mounted) setState(() {});
  }

  Future<void> _loadVideos() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final videos = await TvVideoService.getVideos();
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _isLoading = false;
        if (_videos.isNotEmpty && _currentVideo == null) {
          _setCurrentVideo(_videos.first);
        } else if (_videos.isEmpty) {
          _currentVideo = null;
          _videoController?.dispose();
          _videoController = null;
          _isVideoInitialized = false;
        }
      });
      _generateThumbnails();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Impossible de charger les vidéos.\n(${e.toString()})';
      });
    }
  }

  Future<void> _refreshVideos() async {
    setState(() => _isRefreshing = true);
    try {
      final videos = await TvVideoService.refreshVideos();
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _isRefreshing = false;
        _loadError = null;
        if (_videos.isNotEmpty) {
          final stillExists = _videos.any((v) => v.id == _currentVideo?.id);
          if (!stillExists) {
            _setCurrentVideo(_videos.first);
          }
        } else {
          _currentVideo = null;
          _videoController?.dispose();
          _videoController = null;
          _isVideoInitialized = false;
        }
      });
      _generateThumbnails();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        _loadError = 'Erreur lors du rafraîchissement.';
      });
    }
  }

  // --- Gestion de la vidéo courante ---
  void _setCurrentVideo(TvVideo video) {
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;
    _videoError = false;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;

    setState(() {
      _currentVideo = video;
    });

    debugPrint('Chargement de la vidéo : ${video.videoUrl}');
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(video.videoUrl))
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {
              _isVideoInitialized = true;
              _videoError = false;
              _totalDuration = _videoController!.value.duration;
            });
            
            // Lecture automatique dès l'initialisation réussie
            _videoController!.play();
            setState(() {
              _isPlaying = true;
            });

            _updateLikesAndComments(video.id);
            _videoController!.addListener(_videoListener);
          }).catchError((e) {
            debugPrint('Erreur initialisation vidéo : $e');
            if (!mounted) return;
            setState(() {
              _isVideoInitialized = false;
              _videoError = true;
            });
          });
  }

  void _videoListener() {
    if (!mounted || _videoController == null) return;
    final value = _videoController!.value;
    if (value.position != _currentPosition) {
      setState(() {
        _currentPosition = value.position;
        _totalDuration = value.duration;
        _isPlaying = value.isPlaying;
      });
    }
  }

  // --- Miniatures (video_thumbnail) ---
  Future<void> _generateThumbnails() async {
    for (final video in _videos) {
      if (_thumbnailCache.containsKey(video.id)) continue;
      try {
        final thumbData = await VideoThumbnail.thumbnailData(
          video: video.videoUrl,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 160,
          quality: 70,
        );
        if (thumbData != null) {
          _thumbnailCache[video.id] = thumbData;
          if (mounted) setState(() {});
        }
      } catch (e) {
        debugPrint('Erreur génération miniature pour ${video.id}: $e');
      }
    }
  }

  // --- Likes & Commentaires ---
  Future<void> _updateLikesAndComments(String videoId) async {
    if (_userMatricule == null) return;
    final likes = await TvVideoService.getLikesCount(videoId);
    final liked = await TvVideoService.hasUserLiked(videoId, _userMatricule!);
    if (!mounted) return;
    setState(() {
      _likesCount = likes;
      _userLiked = liked;
    });
    _loadComments(videoId);
  }

  Future<void> _loadComments(String videoId) async {
    if (mounted) setState(() => _isLoadingComments = true);
    final comments = await TvVideoService.getComments(videoId);
    if (mounted) {
      setState(() {
        _comments = comments;
        _isLoadingComments = false;
      });
    }
  }

  Future<void> _handleLike() async {
    if (_currentVideo == null || _userMatricule == null) return;
    await TvVideoService.toggleLike(_currentVideo!.id, _userMatricule!);
    final likes = await TvVideoService.getLikesCount(_currentVideo!.id);
    final liked =
        await TvVideoService.hasUserLiked(_currentVideo!.id, _userMatricule!);
    if (!mounted) return;
    setState(() {
      _likesCount = likes;
      _userLiked = liked;
    });
  }

  void _showCommentDialog() {
    if (_currentVideo == null) return;
    final TextEditingController controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ajouter un commentaire',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Votre commentaire...',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      Navigator.pop(ctx);
                      
                      // On s'assure d'avoir la combinaison nom + prénom à jour
                      final prefs = await SharedPreferences.getInstance();
                      final nom = prefs.getString('nom') ?? '';
                      final prenom = prefs.getString('prenom') ?? '';
                      final fullName = '$nom $prenom'.trim();
                      final currentUserName = fullName.isNotEmpty ? fullName : (_userName ?? 'Anonyme');

                      await TvVideoService.addComment(
                        videoId: _currentVideo!.id,
                        matricule: _userMatricule ?? 'unknown',
                        userName: currentUserName,
                        commentaire: text,
                      );
                      await _loadComments(_currentVideo!.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Commentaire ajouté !')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAppOrange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Publier'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showCommentsView() {
    if (_currentVideo == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.3,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text(
                            'Commentaires',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              await _loadComments(_currentVideo!.id);
                              setStateModal(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isLoadingComments
                          ? const Center(child: CircularProgressIndicator())
                          : _comments.isEmpty
                              ? const Center(
                                  child: Text(
                                      'Aucun commentaire pour l\'instant.'),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: _comments.length,
                                  itemBuilder: (_, index) {
                                    final c = _comments[index];
                                    final name = c['user_name'] ?? 'Anonyme';
                                    final initial = name.trim().isNotEmpty
                                        ? name.trim()[0].toUpperCase()
                                        : '?';
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: kAppOrange,
                                        child: Text(
                                          initial,
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(c['commentaire'] ?? ''),
                                      trailing: Text(
                                        c['created_at'] != null
                                            ? _formatDate(c['created_at'])
                                            : '',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
  }

  // ==========================================================================
  // UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kAppOrange));
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadVideos,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAppOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      return RefreshIndicator(
        color: kAppOrange,
        onRefresh: _refreshVideos,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune vidéo disponible pour le moment.\nRevenez plus tard !',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kAppOrange,
      onRefresh: _refreshVideos,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(color: kAppOrange),
            ),
          _buildVideoPlayer(),
          _buildLikesAndComments(),
          _buildVideoInfo(),
          _buildThumbnails(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- Lecteur vidéo grand format (85% de la hauteur de l'écran) ---
  Widget _buildVideoPlayer() {
    final videoHeight = MediaQuery.of(context).size.height * 0.85;

    if (_currentVideo == null) {
      return Container(
        height: videoHeight,
        color: Colors.black,
        child: const Center(
          child: Text(
            'Sélectionnez une vidéo',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (_videoError) {
      return Container(
        height: videoHeight,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Impossible de lire cette vidéo',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _setCurrentVideo(_currentVideo!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAppOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: videoHeight,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (_isVideoInitialized && _videoController != null)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: kAppOrange),
            ),
          // Overlay des contrôles
          if (_isVideoInitialized && _videoController != null)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Barre de progression
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            _videoController!,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            colors: VideoProgressColors(
                              playedColor: kAppOrange,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(_totalDuration),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Boutons de contrôle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        // Play / Pause
                        IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            if (_videoController!.value.isPlaying) {
                              _videoController!.pause();
                            } else {
                              _videoController!.play();
                            }
                            setState(() {});
                          },
                        ),
                        const Spacer(),
                        // Recul 10s
                        IconButton(
                          icon:
                              const Icon(Icons.replay_10, color: Colors.white),
                          onPressed: () {
                            final newPos =
                                _currentPosition - const Duration(seconds: 10);
                            if (newPos > Duration.zero) {
                              _videoController!.seekTo(newPos);
                            } else {
                              _videoController!.seekTo(Duration.zero);
                            }
                          },
                        ),
                        // Avance rapide 10s
                        IconButton(
                          icon:
                              const Icon(Icons.forward_10, color: Colors.white),
                          onPressed: () {
                            final newPos =
                                _currentPosition + const Duration(seconds: 10);
                            if (newPos < _totalDuration) {
                              _videoController!.seekTo(newPos);
                            } else {
                              _videoController!.seekTo(_totalDuration);
                            }
                          },
                        ),
                        const Spacer(),
                        // Plein écran
                        IconButton(
                          icon:
                              const Icon(Icons.fullscreen, color: Colors.white),
                          onPressed: _openFullScreen,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Plein écran ---
  void _openFullScreen() {
    if (_videoController == null || !_isVideoInitialized) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPage(
          controller: _videoController!,
          videoTitle: _currentVideo?.title ?? '',
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  // --- Section Likes et Commentaires sous la vidéo ---
  Widget _buildLikesAndComments() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Like
          InkWell(
            onTap: _handleLike,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _userLiked
                    ? kAppOrange.withOpacity(0.2)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    _userLiked ? Icons.favorite : Icons.favorite_border,
                    color: _userLiked ? kAppOrange : Colors.grey.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_likesCount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _userLiked ? kAppOrange : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Commentaires
          InkWell(
            onTap: _showCommentsView,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.comment, color: Colors.grey, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    '${_comments.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Bouton ajouter commentaire
          ElevatedButton.icon(
            onPressed: _showCommentDialog,
            icon: const Icon(Icons.add_comment, size: 18),
            label: const Text('Commenter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAppOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // --- Informations de la vidéo (titre, sous-titre, description) ---
  Widget _buildVideoInfo() {
    if (_currentVideo == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currentVideo!.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kAppOrange,
            ),
          ),
          if (_currentVideo!.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _currentVideo!.subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
          if (_currentVideo!.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _currentVideo!.description,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  // --- Miniatures des autres vidéos ---
  Widget _buildThumbnails() {
    final others = _videos.where((v) => v.id != _currentVideo?.id).toList();
    if (others.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: others.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, index) {
          final video = others[index];
          final thumb = _thumbnailCache[video.id];
          return GestureDetector(
            onTap: () => _setCurrentVideo(video),
            child: Container(
              width: 160,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 4,
                    color: Colors.black12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      color: Colors.grey.shade200,
                    ),
                    child: thumb != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            child: Image.memory(
                              thumb,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.play_arrow,
                                color: kAppOrange, size: 32),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// Écran plein écran
// ============================================================================

class FullScreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String videoTitle;

  const FullScreenVideoPage({
    super.key,
    required this.controller,
    required this.videoTitle,
  });

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    widget.controller.addListener(_listener);
    if (!widget.controller.value.isPlaying) {
      widget.controller.play();
    }
    setState(() {
      _isPlaying = widget.controller.value.isPlaying;
      _position = widget.controller.value.position;
      _duration = widget.controller.value.duration;
    });
  }

  void _listener() {
    if (!mounted) return;
    setState(() {
      _isPlaying = widget.controller.value.isPlaying;
      _position = widget.controller.value.position;
      _duration = widget.controller.value.duration;
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _controlsVisible = !_controlsVisible;
          });
        },
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            if (_controlsVisible)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                    stops: const [0.0, 0.3, 1.0],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () {
                                Navigator.pop(context);
                              },
                            ),
                            Expanded(
                              child: Text(
                                widget.videoTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    widget.controller,
                                    allowScrubbing: true,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    colors: VideoProgressColors(
                                      playedColor: kAppOrange,
                                      bufferedColor: Colors.white38,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  onPressed: () {
                                    if (widget.controller.value.isPlaying) {
                                      widget.controller.pause();
                                    } else {
                                      widget.controller.play();
                                    }
                                    setState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.replay_10,
                                      color: Colors.white),
                                  onPressed: () {
                                    final newPos =
                                        _position - const Duration(seconds: 10);
                                    widget.controller.seekTo(
                                        newPos > Duration.zero
                                            ? newPos
                                            : Duration.zero);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.forward_10,
                                      color: Colors.white),
                                  onPressed: () {
                                    final newPos =
                                        _position + const Duration(seconds: 10);
                                    widget.controller.seekTo(newPos < _duration
                                        ? newPos
                                        : _duration);
                                  },
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.fullscreen_exit,
                                      color: Colors.white),
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}