#ifndef RUNNER_WINDOWS_MEDIA_SESSION_H_
#define RUNNER_WINDOWS_MEDIA_SESSION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class WindowsMediaSessionBridge
    : public std::enable_shared_from_this<WindowsMediaSessionBridge> {
 public:
  static std::shared_ptr<WindowsMediaSessionBridge> Create(
      flutter::BinaryMessenger* messenger, HWND window);

  ~WindowsMediaSessionBridge();

  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  class Impl;

  WindowsMediaSessionBridge(flutter::BinaryMessenger* messenger, HWND window);

  void RegisterMethodHandler();
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void EmitCommand(const char* type, int64_t position_ms = -1);
  void EmitVolume(double level, bool muted);
  void EmitVolumeSessionDisconnected();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_WINDOWS_MEDIA_SESSION_H_
