#include "windows_media_session.h"

#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

namespace {

constexpr UINT kWindowsMediaMessage = WM_APP + 0x3A1;

enum class NativeMediaEvent : WPARAM {
  kPlay = 1,
  kPause = 2,
  kNext = 3,
  kPrevious = 4,
  kStop = 5,
  kSeek = 6,
  kVolumeChanged = 20,
  kVolumeSessionDisconnected = 21,
};

const flutter::EncodableMap* ReadArguments(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  return std::get_if<flutter::EncodableMap>(call.arguments());
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap* map,
                                         const char* key) {
  if (map == nullptr) {
    return nullptr;
  }
  const auto found = map->find(flutter::EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}

std::string ReadString(const flutter::EncodableMap* map, const char* key) {
  const auto* value = FindValue(map, key);
  const auto* text =
      value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? std::string() : *text;
}

bool ReadBool(const flutter::EncodableMap* map, const char* key,
              bool fallback = false) {
  const auto* value = FindValue(map, key);
  const auto* boolean =
      value == nullptr ? nullptr : std::get_if<bool>(value);
  return boolean == nullptr ? fallback : *boolean;
}

int64_t ReadInt64(const flutter::EncodableMap* map, const char* key,
                  int64_t fallback = 0) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  return fallback;
}

double ReadDouble(const flutter::EncodableMap* map, const char* key,
                  double fallback = 0.0) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* number = std::get_if<double>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<double>(*number);
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return static_cast<double>(*number);
  }
  return fallback;
}

winrt::Windows::Foundation::TimeSpan MillisecondsToTimeSpan(
    int64_t milliseconds) {
  using winrt::Windows::Foundation::TimeSpan;
  return std::chrono::duration_cast<TimeSpan>(
      std::chrono::milliseconds(std::max<int64_t>(0, milliseconds)));
}

class AudioSessionEvents final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          IAudioSessionEvents> {
 public:
  void SetWindow(HWND window) { window_ = window; }

  IFACEMETHODIMP OnDisplayNameChanged(LPCWSTR, LPCGUID) override {
    return S_OK;
  }
  IFACEMETHODIMP OnIconPathChanged(LPCWSTR, LPCGUID) override {
    return S_OK;
  }
  IFACEMETHODIMP OnSimpleVolumeChanged(float new_volume, BOOL new_mute,
                                       LPCGUID) override {
    const auto level = static_cast<WPARAM>(std::lround(
        std::clamp(new_volume, 0.0f, 1.0f) * 10000.0f));
    const WPARAM packed = level | (new_mute ? (WPARAM{1} << 16) : 0);
    ::PostMessage(window_, kWindowsMediaMessage,
                  static_cast<WPARAM>(NativeMediaEvent::kVolumeChanged),
                  static_cast<LPARAM>(packed));
    return S_OK;
  }
  IFACEMETHODIMP OnChannelVolumeChanged(DWORD, float[], DWORD,
                                        LPCGUID) override {
    return S_OK;
  }
  IFACEMETHODIMP OnGroupingParamChanged(LPCGUID, LPCGUID) override {
    return S_OK;
  }
  IFACEMETHODIMP OnStateChanged(AudioSessionState) override { return S_OK; }
  IFACEMETHODIMP OnSessionDisconnected(
      AudioSessionDisconnectReason) override {
    ::PostMessage(
        window_, kWindowsMediaMessage,
        static_cast<WPARAM>(NativeMediaEvent::kVolumeSessionDisconnected), 0);
    return S_OK;
  }

 private:
  HWND window_ = nullptr;
};

}  // namespace

class WindowsMediaSessionBridge::Impl {
 public:
  explicit Impl(HWND window)
      : window_(window),
        metadata_generation_(std::make_shared<std::atomic<uint64_t>>(0)) {}

  ~Impl() { Dispose(); }

  bool InitializeSmtc() {
    if (controls_) {
      return true;
    }
    try {
      auto interop = winrt::get_activation_factory<
          winrt::Windows::Media::SystemMediaTransportControls,
          ISystemMediaTransportControlsInterop>();
      winrt::check_hresult(interop->GetForWindow(
          window_,
          winrt::guid_of<
              winrt::Windows::Media::ISystemMediaTransportControls>(),
          winrt::put_abi(controls_)));
      button_pressed_token_ = controls_.ButtonPressed(
          [window = window_](const auto&, const auto& args) {
            using winrt::Windows::Media::SystemMediaTransportControlsButton;
            NativeMediaEvent event{};
            switch (args.Button()) {
              case SystemMediaTransportControlsButton::Play:
                event = NativeMediaEvent::kPlay;
                break;
              case SystemMediaTransportControlsButton::Pause:
                event = NativeMediaEvent::kPause;
                break;
              case SystemMediaTransportControlsButton::Next:
                event = NativeMediaEvent::kNext;
                break;
              case SystemMediaTransportControlsButton::Previous:
                event = NativeMediaEvent::kPrevious;
                break;
              case SystemMediaTransportControlsButton::Stop:
                event = NativeMediaEvent::kStop;
                break;
              default:
                break;
            }
            if (event != NativeMediaEvent{}) {
              ::PostMessage(window, kWindowsMediaMessage,
                            static_cast<WPARAM>(event), 0);
            }
          });
      position_requested_token_ = controls_.PlaybackPositionChangeRequested(
          [window = window_](const auto&, const auto& args) {
            const auto milliseconds =
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    args.RequestedPlaybackPosition())
                    .count();
            ::PostMessage(window, kWindowsMediaMessage,
                          static_cast<WPARAM>(NativeMediaEvent::kSeek),
                          static_cast<LPARAM>(milliseconds));
          });
      smtc_events_registered_ = true;
      return true;
    } catch (...) {
      controls_ = nullptr;
      return false;
    }
  }

  void UpdateMetadata(const flutter::EncodableMap* arguments) {
    if (!controls_) {
      return;
    }
    const auto title = ReadString(arguments, "title");
    const auto subtitle = ReadString(arguments, "subtitle");
    const auto artwork_path = ReadString(arguments, "artworkPath");
    const uint64_t generation = ++(*metadata_generation_);
    try {
      auto updater = controls_.DisplayUpdater();
      updater.ClearAll();
      updater.Type(winrt::Windows::Media::MediaPlaybackType::Video);
      auto properties = updater.VideoProperties();
      properties.Title(winrt::to_hstring(title));
      properties.Subtitle(winrt::to_hstring(subtitle));
      updater.Update();

      if (!artwork_path.empty()) {
        const auto generation_state = metadata_generation_;
        auto operation = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(
            winrt::to_hstring(artwork_path));
        operation.Completed(
            [updater, generation_state, generation](
                const auto& sender,
                winrt::Windows::Foundation::AsyncStatus status) {
              if (status != winrt::Windows::Foundation::AsyncStatus::Completed ||
                  generation_state->load() != generation) {
                return;
              }
              try {
                updater.Thumbnail(
                    winrt::Windows::Storage::Streams::
                        RandomAccessStreamReference::CreateFromFile(
                            sender.GetResults()));
                updater.Update();
              } catch (...) {
                // Text metadata remains valid when artwork cannot be opened.
              }
            });
      }
    } catch (...) {
      // SMTC is best-effort and must never break playback.
    }
  }

  void UpdatePlayback(const flutter::EncodableMap* arguments) {
    if (!controls_) {
      return;
    }
    try {
      using winrt::Windows::Media::MediaPlaybackStatus;
      const auto state = ReadString(arguments, "state");
      controls_.IsEnabled(true);
      controls_.IsPlayEnabled(true);
      controls_.IsPauseEnabled(true);
      controls_.IsStopEnabled(true);
      controls_.IsPreviousEnabled(ReadBool(arguments, "canPrevious"));
      controls_.IsNextEnabled(ReadBool(arguments, "canNext"));
      controls_.PlaybackStatus(
          state == "playing"
              ? MediaPlaybackStatus::Playing
              : state == "changing"
                    ? MediaPlaybackStatus::Changing
                    : state == "stopped" ? MediaPlaybackStatus::Stopped
                                         : MediaPlaybackStatus::Paused);
    } catch (...) {
      // Ignore unavailable SMTC state updates.
    }
  }

  void UpdateTimeline(const flutter::EncodableMap* arguments) {
    if (!controls_) {
      return;
    }
    const int64_t duration_ms =
        std::max<int64_t>(0, ReadInt64(arguments, "durationMs"));
    const int64_t position_ms = std::clamp<int64_t>(
        ReadInt64(arguments, "positionMs"), 0, duration_ms);
    try {
      winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties
          timeline;
      timeline.StartTime(MillisecondsToTimeSpan(0));
      timeline.MinSeekTime(MillisecondsToTimeSpan(0));
      timeline.Position(MillisecondsToTimeSpan(position_ms));
      timeline.MaxSeekTime(MillisecondsToTimeSpan(duration_ms));
      timeline.EndTime(MillisecondsToTimeSpan(duration_ms));
      controls_.UpdateTimelineProperties(timeline);
    } catch (...) {
      // Timeline support varies by the active Windows shell.
    }
  }

  std::optional<std::pair<double, bool>> BindVolume() {
    UnbindVolume();

    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> device_enumerator;
    Microsoft::WRL::ComPtr<IMMDevice> device;
    Microsoft::WRL::ComPtr<IAudioSessionManager2> session_manager;
    Microsoft::WRL::ComPtr<IAudioSessionEnumerator> session_enumerator;
    if (FAILED(::CoCreateInstance(
            __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
            IID_PPV_ARGS(&device_enumerator))) ||
        FAILED(device_enumerator->GetDefaultAudioEndpoint(
            eRender, eMultimedia, &device)) ||
        FAILED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL,
                                nullptr,
                                reinterpret_cast<void**>(
                                    session_manager.GetAddressOf()))) ||
        FAILED(session_manager->GetSessionEnumerator(&session_enumerator))) {
      return std::nullopt;
    }

    int count = 0;
    if (FAILED(session_enumerator->GetCount(&count))) {
      return std::nullopt;
    }
    Microsoft::WRL::ComPtr<IAudioSessionControl> fallback;
    for (int index = 0; index < count; index++) {
      Microsoft::WRL::ComPtr<IAudioSessionControl> session;
      Microsoft::WRL::ComPtr<IAudioSessionControl2> session2;
      DWORD process_id = 0;
      if (FAILED(session_enumerator->GetSession(index, &session)) ||
          FAILED(session.As(&session2)) ||
          FAILED(session2->GetProcessId(&process_id)) ||
          process_id != ::GetCurrentProcessId()) {
        continue;
      }
      AudioSessionState state = AudioSessionStateInactive;
      session->GetState(&state);
      if (state == AudioSessionStateActive) {
        audio_session_control_ = session;
        break;
      }
      if (!fallback) {
        fallback = session;
      }
    }
    if (!audio_session_control_) {
      audio_session_control_ = fallback;
    }
    if (!audio_session_control_ ||
        FAILED(audio_session_control_.As(&simple_volume_))) {
      UnbindVolume();
      return std::nullopt;
    }

    audio_events_ = Microsoft::WRL::Make<AudioSessionEvents>();
    audio_events_->SetWindow(window_);
    if (FAILED(audio_session_control_->RegisterAudioSessionNotification(
            audio_events_.Get()))) {
      UnbindVolume();
      return std::nullopt;
    }

    float level = 1.0f;
    BOOL muted = FALSE;
    if (FAILED(simple_volume_->GetMasterVolume(&level)) ||
        FAILED(simple_volume_->GetMute(&muted))) {
      UnbindVolume();
      return std::nullopt;
    }
    return std::pair<double, bool>(
        std::clamp(static_cast<double>(level) * 100.0, 0.0, 100.0),
        muted == TRUE);
  }

  bool SetVolume(double level) {
    if (!simple_volume_) {
      return false;
    }
    const double normalized = std::clamp(level, 0.0, 100.0);
    if (normalized <= 0.0) {
      return SUCCEEDED(simple_volume_->SetMute(TRUE, nullptr));
    }
    const bool volume_set = SUCCEEDED(simple_volume_->SetMasterVolume(
        static_cast<float>(normalized / 100.0), nullptr));
    const bool unmuted = SUCCEEDED(simple_volume_->SetMute(FALSE, nullptr));
    return volume_set && unmuted;
  }

  void Clear() {
    ++(*metadata_generation_);
    if (!controls_) {
      return;
    }
    try {
      controls_.PlaybackStatus(
          winrt::Windows::Media::MediaPlaybackStatus::Stopped);
      controls_.DisplayUpdater().ClearAll();
      controls_.DisplayUpdater().Update();
      controls_.IsEnabled(false);
    } catch (...) {
      // The shell may already have released the session during shutdown.
    }
  }

  void Dispose() {
    Clear();
    UnbindVolume();
    if (controls_ && smtc_events_registered_) {
      try {
        controls_.ButtonPressed(button_pressed_token_);
        controls_.PlaybackPositionChangeRequested(position_requested_token_);
      } catch (...) {
        // Ignore teardown races with the Windows shell.
      }
    }
    smtc_events_registered_ = false;
    controls_ = nullptr;
  }

 private:
  void UnbindVolume() {
    if (audio_session_control_ && audio_events_) {
      audio_session_control_->UnregisterAudioSessionNotification(
          audio_events_.Get());
    }
    audio_events_.Reset();
    simple_volume_.Reset();
    audio_session_control_.Reset();
  }

  HWND window_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_pressed_token_{};
  winrt::event_token position_requested_token_{};
  bool smtc_events_registered_ = false;
  std::shared_ptr<std::atomic<uint64_t>> metadata_generation_;
  Microsoft::WRL::ComPtr<IAudioSessionControl> audio_session_control_;
  Microsoft::WRL::ComPtr<ISimpleAudioVolume> simple_volume_;
  Microsoft::WRL::ComPtr<AudioSessionEvents> audio_events_;
};

std::shared_ptr<WindowsMediaSessionBridge> WindowsMediaSessionBridge::Create(
    flutter::BinaryMessenger* messenger, HWND window) {
  auto bridge = std::shared_ptr<WindowsMediaSessionBridge>(
      new WindowsMediaSessionBridge(messenger, window));
  bridge->RegisterMethodHandler();
  return bridge;
}

WindowsMediaSessionBridge::WindowsMediaSessionBridge(
    flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<
               flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "peek/windows_media_session",
          &flutter::StandardMethodCodec::GetInstance())),
      impl_(std::make_unique<Impl>(window)) {}

WindowsMediaSessionBridge::~WindowsMediaSessionBridge() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void WindowsMediaSessionBridge::RegisterMethodHandler() {
  const std::weak_ptr<WindowsMediaSessionBridge> weak = shared_from_this();
  channel_->SetMethodCallHandler(
      [weak](const auto& call, auto result) {
        if (const auto bridge = weak.lock()) {
          bridge->HandleMethodCall(call, std::move(result));
        } else {
          result->NotImplemented();
        }
      });
}

void WindowsMediaSessionBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();
  const auto* arguments = ReadArguments(method_call);
  if (method == "initialize") {
    const bool smtc_available = impl_->InitializeSmtc();
    flutter::EncodableMap response;
    response[flutter::EncodableValue("available")] =
        flutter::EncodableValue(true);
    response[flutter::EncodableValue("smtc")] =
        flutter::EncodableValue(smtc_available);
    result->Success(flutter::EncodableValue(response));
    return;
  }
  if (method == "updateMetadata") {
    impl_->UpdateMetadata(arguments);
    result->Success();
    return;
  }
  if (method == "updatePlayback") {
    impl_->UpdatePlayback(arguments);
    result->Success();
    return;
  }
  if (method == "updateTimeline") {
    impl_->UpdateTimeline(arguments);
    result->Success();
    return;
  }
  if (method == "bindVolume") {
    const auto volume = impl_->BindVolume();
    if (!volume) {
      result->Success(flutter::EncodableValue());
      return;
    }
    flutter::EncodableMap response;
    response[flutter::EncodableValue("level")] =
        flutter::EncodableValue(volume->first);
    response[flutter::EncodableValue("muted")] =
        flutter::EncodableValue(volume->second);
    result->Success(flutter::EncodableValue(response));
    return;
  }
  if (method == "setVolume") {
    result->Success(flutter::EncodableValue(
        impl_->SetVolume(ReadDouble(arguments, "level", 100.0))));
    return;
  }
  if (method == "clear") {
    impl_->Clear();
    result->Success();
    return;
  }
  if (method == "dispose") {
    impl_->Dispose();
    result->Success();
    return;
  }
  result->NotImplemented();
}

bool WindowsMediaSessionBridge::HandleWindowMessage(UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam) {
  if (message != kWindowsMediaMessage) {
    return false;
  }
  switch (static_cast<NativeMediaEvent>(wparam)) {
    case NativeMediaEvent::kPlay:
      EmitCommand("play");
      break;
    case NativeMediaEvent::kPause:
      EmitCommand("pause");
      break;
    case NativeMediaEvent::kNext:
      EmitCommand("next");
      break;
    case NativeMediaEvent::kPrevious:
      EmitCommand("previous");
      break;
    case NativeMediaEvent::kStop:
      EmitCommand("stop");
      break;
    case NativeMediaEvent::kSeek:
      EmitCommand("seek", static_cast<int64_t>(lparam));
      break;
    case NativeMediaEvent::kVolumeChanged: {
      const auto packed = static_cast<WPARAM>(lparam);
      const double level =
          std::clamp(static_cast<double>(packed & 0xFFFF) / 100.0, 0.0,
                     100.0);
      EmitVolume(level, (packed & (WPARAM{1} << 16)) != 0);
      break;
    }
    case NativeMediaEvent::kVolumeSessionDisconnected:
      EmitVolumeSessionDisconnected();
      break;
  }
  return true;
}

void WindowsMediaSessionBridge::EmitCommand(const char* type,
                                            int64_t position_ms) {
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("type")] =
      flutter::EncodableValue(type);
  if (position_ms >= 0) {
    arguments[flutter::EncodableValue("positionMs")] =
        flutter::EncodableValue(position_ms);
  }
  channel_->InvokeMethod(
      "command", std::make_unique<flutter::EncodableValue>(arguments));
}

void WindowsMediaSessionBridge::EmitVolume(double level, bool muted) {
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("level")] =
      flutter::EncodableValue(level);
  arguments[flutter::EncodableValue("muted")] =
      flutter::EncodableValue(muted);
  channel_->InvokeMethod(
      "volumeChanged",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void WindowsMediaSessionBridge::EmitVolumeSessionDisconnected() {
  channel_->InvokeMethod(
      "volumeSessionDisconnected",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableMap()));
}
