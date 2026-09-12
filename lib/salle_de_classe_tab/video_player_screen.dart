import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _isError = false;
  String? _errorMessage;

  bool _showControls = true;
  final ValueNotifier<Duration> _videoPosition = ValueNotifier(Duration.zero);
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(1.0);
  bool _isMuted = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();
      _controller!.addListener(_videoListener);
      // Initialiser le volume
      _controller!.setVolume(_isMuted ? 0.0 : _volumeNotifier.value);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = false;
          _errorMessage = null;
        });
        await _controller!.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage =
              "La vidéo sera disponible très bientôt, soyez patients.";
        });
      }
    }
  }

  void _videoListener() {
    if (_controller != null && _controller!.value.isInitialized) {
      _videoPosition.value = _controller!.value.position;
      // On met à jour la durée si elle change (utile pour les vidéos en direct)
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _controller!.setVolume(_isMuted ? 0.0 : _volumeNotifier.value);
  }

  void _changeVolume(double value) {
    _volumeNotifier.value = value;
    if (!_isMuted) {
      _controller!.setVolume(value);
    }
  }

  @override
  void dispose() {
    if (_controller != null) {
      _controller!.removeListener(_videoListener);
      _controller!.dispose();
    }
    _videoPosition.dispose();
    _volumeNotifier.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen
          ? null
          : AppBar(
              title: Text(widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFFFF8C00),
              centerTitle: true,
              elevation: 0,
              foregroundColor: Colors.white,
            ),
      body: _isLoading
          ? _buildLoadingWidget()
          : _isError
              ? _buildErrorWidget()
              : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: Colors.black,
          child: Stack(
            children: [
              // Vidéo – affichage normal (pas de zoom par défaut)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),
              // Overlay des contrôles (affichés/masqués par tap)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showControls = !_showControls;
                    });
                  },
                  child: _showControls
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Barre de progression
                              ValueListenableBuilder<Duration>(
                                valueListenable: _videoPosition,
                                builder: (context, position, child) {
                                  final total = _controller!.value.duration;
                                  if (total == Duration.zero) {
                                    return const SizedBox.shrink();
                                  }
                                  return Row(
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: position.inSeconds
                                              .toDouble()
                                              .clamp(0.0,
                                                  total.inSeconds.toDouble()),
                                          min: 0,
                                          max: total.inSeconds.toDouble(),
                                          activeColor: const Color(0xFFFF8C00),
                                          inactiveColor: Colors.grey.shade300,
                                          thumbColor: const Color(0xFFFF8C00),
                                          onChanged: (value) {
                                            _controller!.seekTo(Duration(
                                                seconds: value.toInt()));
                                          },
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(total),
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              // Ligne de boutons : Play, avance/recule, volume, plein écran
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Volume
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          _isMuted
                                              ? Icons.volume_off
                                              : Icons.volume_up,
                                          color: Colors.white,
                                        ),
                                        onPressed: _toggleMute,
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: _volumeNotifier,
                                          builder: (context, volume, child) {
                                            return Slider(
                                              value: volume,
                                              min: 0,
                                              max: 1,
                                              activeColor:
                                                  const Color(0xFFFF8C00),
                                              inactiveColor: Colors.grey,
                                              onChanged: _changeVolume,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  // Recul 10s
                                  _controlButton(
                                    icon: Icons.replay_10,
                                    onPressed: () {
                                      final current =
                                          _controller!.value.position;
                                      _controller!.seekTo(current -
                                          const Duration(seconds: 10));
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  // Play/Pause
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF8C00),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        _controller!.value.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                      ),
                                      onPressed: _togglePlayPause,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Avance 10s
                                  _controlButton(
                                    icon: Icons.forward_10,
                                    onPressed: () {
                                      final current =
                                          _controller!.value.position;
                                      _controller!.seekTo(current +
                                          const Duration(seconds: 10));
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  // Plein écran
                                  _controlButton(
                                    icon: _isFullScreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    onPressed: _toggleFullScreen,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controlButton(
      {required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, size: 22, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8C00)),
          ),
          const SizedBox(height: 16),
          const Text("Chargement de la vidéo...",
              style: TextStyle(
                  color: Color(0xFFFF8C00), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty,
                size: 60, color: Color(0xFFFF8C00)),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? "Vidéo indisponible pour le moment.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Nous mettons tout en œuvre pour vous la proposer rapidement.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text("Retour",
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _isError = false;
                  _errorMessage = null;
                });
                _initializeVideo();
              },
              child: const Text("Réessayer plus tard",
                  style: TextStyle(color: Color(0xFFFF8C00))),
            ),
          ],
        ),
      ),
    );
  }
}
