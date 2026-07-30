import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Inline call-recording player - streams and plays the recording URL directly
/// (AudioPlayer.play(UrlSource(...)) streams, it does not save a file to disk),
/// so listening never triggers a device download or leaves the app.
class CallRecordingPlayer extends StatefulWidget {
  final String url;
  final Color accentColor;

  const CallRecordingPlayer({super.key, required this.url, this.accentColor = const Color(0xFFC09E3E)});

  @override
  State<CallRecordingPlayer> createState() => _CallRecordingPlayerState();
}

class _CallRecordingPlayerState extends State<CallRecordingPlayer> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _player.play(UrlSource(widget.url));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play recording');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    final total = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final pos = _position.inMilliseconds.clamp(0, total.toInt()).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _loading
              ? SizedBox(
                  width: 32, height: 32,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor),
                  ),
                )
              : IconButton(
                  icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                  color: widget.accentColor,
                  iconSize: 32,
                  padding: EdgeInsets.zero,
                  onPressed: _toggle,
                ),
          Expanded(
            child: _error != null
                ? Text(_error!, style: const TextStyle(fontSize: 11.5, color: Colors.red))
                : SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: pos,
                      max: total,
                      activeColor: widget.accentColor,
                      inactiveColor: widget.accentColor.withValues(alpha: 0.2),
                      onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
          ),
          Text(
            _duration.inMilliseconds > 0 ? '${_fmt(_position)} / ${_fmt(_duration)}' : 'Recording',
            style: TextStyle(fontSize: 10.5, color: widget.accentColor),
          ),
        ],
      ),
    );
  }
}
