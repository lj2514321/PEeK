import 'package:embyplayer/src/features/player/data/playback_device_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a complete server device profile with the selected bitrate', () {
    final profile = PlaybackDeviceProfile.build(maxStreamingBitrate: 20000000);

    expect(profile['Name'], 'PEeK Windows');
    expect(profile['SupportedMediaTypes'], 'Video,Audio');
    expect(profile['MaxStreamingBitrate'], 20000000);
    expect(profile['DirectPlayProfiles'], isNotEmpty);
    expect(profile['TranscodingProfiles'], isNotEmpty);
    expect(profile['ContainerProfiles'], isA<List<Object>>());
    expect(profile['CodecProfiles'], isA<List<Object>>());
    expect(profile['SubtitleProfiles'], isNotEmpty);
  });

  test('keeps bitrate values isolated between profile builds', () {
    final limited = PlaybackDeviceProfile.build(maxStreamingBitrate: 10000000);
    final original = PlaybackDeviceProfile.build(
      maxStreamingBitrate: 160000000,
    );

    expect(limited['MaxStreamingBitrate'], 10000000);
    expect(original['MaxStreamingBitrate'], 160000000);
  });

  test('declares external text and embedded styled or bitmap subtitles', () {
    final profile = PlaybackDeviceProfile.build(maxStreamingBitrate: 160000000);
    final subtitles = (profile['SubtitleProfiles'] as List<Object>)
        .cast<Map<String, Object>>();
    bool hasProfile(String format, String method) {
      return subtitles.any(
        (profile) => profile['Format'] == format && profile['Method'] == method,
      );
    }

    expect(hasProfile('srt', 'External'), isTrue);
    expect(hasProfile('vtt', 'External'), isTrue);
    expect(hasProfile('ass', 'Embed'), isTrue);
    expect(hasProfile('pgssub', 'Embed'), isTrue);
  });

  test('uses HLS as the video transcoding fallback', () {
    final profile = PlaybackDeviceProfile.build(maxStreamingBitrate: 160000000);
    final transcoding = (profile['TranscodingProfiles'] as List<Object>)
        .cast<Map<String, Object>>()
        .single;

    expect(transcoding['Container'], 'ts');
    expect(transcoding['Protocol'], 'hls');
    expect(transcoding['VideoCodec'], 'h264,hevc');
    expect(transcoding['AudioCodec'], contains('aac'));
  });
}
