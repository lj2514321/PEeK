abstract final class PlaybackDeviceProfile {
  static Map<String, dynamic> build({required int maxStreamingBitrate}) {
    return <String, dynamic>{
      'Name': 'PEeK Windows',
      'SupportedMediaTypes': 'Video,Audio',
      'MaxStreamingBitrate': maxStreamingBitrate,
      'MusicStreamingTranscodingBitrate': 320000,
      'DirectPlayProfiles': _directPlayProfiles,
      'TranscodingProfiles': _transcodingProfiles,
      'ContainerProfiles': const <Map<String, Object>>[],
      'CodecProfiles': const <Map<String, Object>>[],
      'SubtitleProfiles': _subtitleProfiles,
    };
  }

  static const _directPlayProfiles = <Map<String, Object>>[
    {
      'Container':
          'mkv,mp4,m4v,mov,avi,ts,m2ts,mpeg,mpg,webm,wmv,flv,vob,ogv,3gp',
      'Type': 'Video',
    },
    {'Container': 'mp3,aac,m4a,flac,ogg,opus,wav,wma', 'Type': 'Audio'},
  ];

  static const _transcodingProfiles = <Map<String, Object>>[
    {
      'Container': 'ts',
      'Type': 'Video',
      'VideoCodec': 'h264,hevc',
      'AudioCodec': 'aac,ac3,eac3,mp3,opus',
      'Protocol': 'hls',
      'Context': 'Streaming',
      'MinSegments': 1,
      'BreakOnNonKeyFrames': true,
    },
  ];

  static const _subtitleProfiles = <Map<String, Object>>[
    {'Format': 'srt', 'Method': 'External'},
    {'Format': 'vtt', 'Method': 'External'},
    {'Format': 'ass', 'Method': 'Embed'},
    {'Format': 'ssa', 'Method': 'Embed'},
    {'Format': 'pgssub', 'Method': 'Embed'},
    {'Format': 'dvdsub', 'Method': 'Embed'},
  ];
}
