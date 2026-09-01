import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

/// Inline call-recording player + download. The raw Knowlarity recording URL
/// 401s for any client that can't attach the provider's API credentials (no
/// browser <audio> element or mobile player can), so:
/// - Listen: fetches bytes through the CRM's authenticated proxy
///   (ApiService.fetchCallRecordingBytes) and plays them via BytesSource -
///   streamed into memory and played, never written to disk.
/// - Download: opens ApiService.callRecordingDownloadUrl (auth via a token
///   query param, since a plain URL open can't carry a header) with
///   Content-Disposition: attachment, so the OS/browser saves an actual file.
class CallRecordingPlayer extends StatefulWidget {
  final int callLogId;
  final Color accentColor;

  /// When set, streams via the account-scoped recording endpoint
  /// (`/api/accounts/{accountId}/call-recording/{id}`) so a salesman can play a
  /// telecaller's recording for the same customer. Omit for a telecaller
  /// viewing their own calls.
  final String? accountId;

  const CallRecordingPlayer({
    super.key,
    required this.callLogId,
    this.accountId,
    this.accentColor = const Color(0xFFC09E3E),
  });

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
  Uint8List? _bytes; // cached after first fetch so replay doesn't re-download

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

  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final uri = Uri.parse(ApiService.callRecordingDownloadUrl(widget.callLogId, accountId: widget.accountId));
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        setState(() => _error = 'Could not start download');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
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
      var bytes = _bytes;
      bytes ??= await ApiService.fetchCallRecordingBytes(widget.callLogId, accountId: widget.accountId);
      if (bytes == null) {
        if (mounted) setState(() => _error = 'Could not load recording');
        return;
      }
      _bytes = bytes;
      await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    } catch (e) {
      // Some platform decoders (notably Windows Media Foundation) reject the
      // narrowband/low-bitrate MP3 variant Knowlarity records calls in, even
      // though the bytes are a valid recording - "Open Externally" hands the
      // same audio to the OS's own player/app as a fallback.
      debugPrint('CallRecordingPlayer: play failed for log ${widget.callLogId}: $e');
      if (mounted) setState(() => _error = 'Could not play in-app — try "Open Externally" below');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.parse(ApiService.callRecordingStreamUrl(widget.callLogId, accountId: widget.accountId));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      setState(() => _error = 'Could not open recording externally');
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
                ? Row(
                    children: [
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(fontSize: 11.5, color: Colors.red)),
                      ),
                      TextButton(
                        onPressed: _openExternally,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Open Externally', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  )
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
          _downloading
              ? SizedBox(
                  width: 32, height: 32,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_rounded),
                  color: widget.accentColor,
                  iconSize: 20,
                  tooltip: 'Download recording',
                  padding: EdgeInsets.zero,
                  onPressed: _download,
                ),
        ],
      ),
    );
  }
}
