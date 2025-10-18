import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة just_audio_background (لازم قبل تشغيل التطبيق)
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.app.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlayerModel(),
      child: MaterialApp(
        title: 'Audio Background Demo',
        home: const HomePage(),
      ),
    );
  }
}

class PlayerModel extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  AudioPlayer get player => _player;

  PlayerModel() {
    _setup();
  }

  Future<void> _setup() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // استمع للأخطاء أو للحالة لو احتجت
    _player.playbackEventStream.listen(
      (event) {
        notifyListeners();
      },
      onError: (e, st) {
        debugPrint('Player error: $e');
      },
    );
  }

  Future<void> setFileFromPath(String path) async {
    try {
      // استخدم AudioSource.file مع metadeta لإظهار اسم في الإشعار
      final mediaItem = MediaItem(
        id: path,
        album: "Local",
        title: File(path).uri.pathSegments.last,
      );
      await _player.setAudioSource(
        AudioSource.uri(Uri.file(path), tag: mediaItem),
        preload: true,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading file: $e');
    }
  }

  Future<void> setAsset(String assetPath, String title) async {
    final mediaItem = MediaItem(id: assetPath, album: "Asset", title: title);
    await _player.setAudioSource(
      AudioSource.asset(assetPath, tag: mediaItem),
      preload: true,
    );
    notifyListeners();
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        final model = Provider.of<PlayerModel>(context, listen: false);
        await model.setFileFromPath(path);
        await model.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<PlayerModel>(context);
    final player = model.player;

    return Scaffold(
      appBar: AppBar(title: const Text('مشغل صوتي + خلفية')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _pickFile(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('اختر ملف من الهاتف'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                // مثال لتشغيل ملف من assets (أضف ملف صوتي في pubspec assets)
                await model.setAsset('assets/audio/sample.mp3', 'Sample Asset');
                await model.play();
              },
              icon: const Icon(Icons.audiotrack),
              label: const Text('شغل ملف من التطبيق (assets)'),
            ),
            const SizedBox(height: 20),
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (context, snapshot) {
                final state = snapshot.data;
                final playing = state?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 48,
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                      ),
                      onPressed: () {
                        if (playing) {
                          model.pause();
                        } else {
                          model.play();
                        }
                      },
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.stop_circle),
                      onPressed: () => model.stop(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // شريط تقدم بسيط
            StreamBuilder<Duration?>(
              stream: player.durationStream,
              builder: (context, snapDur) {
                final total = snapDur.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, snapPos) {
                    final pos = snapPos.data ?? Duration.zero;
                    final percent = total.inMilliseconds == 0
                        ? 0.0
                        : pos.inMilliseconds / total.inMilliseconds;
                    return Column(
                      children: [
                        LinearProgressIndicator(value: percent),
                        const SizedBox(height: 8),
                        Text('${_format(pos)} / ${_format(total)}'),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'ملاحظة: عند التشغيل في الخلفية سيظهر إشعار للتحكم ويستمر التشغيل حتى لو إقفلت التطبيق.',
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$mm:$ss';
  }
}
