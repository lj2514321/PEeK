#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include <memory>
#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "windows_media_session.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* registry = flutter_view_controller->engine();
    RegisterPlugins(registry);

    if (flutter_view_controller->view() != nullptr) {
      HWND child_native = flutter_view_controller->view()->GetNativeWindow();
      HWND root_hwnd = ::GetAncestor(child_native, GA_ROOT);
      if (root_hwnd != nullptr) {
        constexpr DWORD kDwmCornerPreferenceRound = 2;
        constexpr DWORD kDwmwaWindowCornerPreference = 33;
        constexpr DWORD kDwmwaBorderColor = 34;
        constexpr COLORREF kDwmwaColorNone = 0xFFFFFFFE;
        constexpr DWORD kDwmwaUseImmersiveDarkMode = 20;

        DwmSetWindowAttribute(root_hwnd, kDwmwaWindowCornerPreference,
                              &kDwmCornerPreferenceRound,
                              sizeof(kDwmCornerPreferenceRound));
        const COLORREF border_color = kDwmwaColorNone;
        DwmSetWindowAttribute(root_hwnd, kDwmwaBorderColor,
                              &border_color, sizeof(border_color));
        BOOL enable_dark_mode = TRUE;
        DwmSetWindowAttribute(root_hwnd, kDwmwaUseImmersiveDarkMode,
                              &enable_dark_mode, sizeof(enable_dark_mode));

        static std::map<HWND, std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>> g_subwindow_channels;
        auto subwindow_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registry->messenger(), "peek/subwindow",
            &flutter::StandardMethodCodec::GetInstance());
        subwindow_channel->SetMethodCallHandler([root_hwnd](const auto& call, auto result) {
          if (call.method_name() == "destroyWindow") {
            ::PostMessage(root_hwnd, WM_CLOSE, 0, 0);
            result->Success();
            g_subwindow_channels.erase(root_hwnd);
          } else {
            result->NotImplemented();
          }
        });
        g_subwindow_channels[root_hwnd] = std::move(subwindow_channel);
      }
    }
  });
  windows_media_session_ = WindowsMediaSessionBridge::Create(
      flutter_controller_->engine()->messenger(), GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  windows_media_session_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (windows_media_session_ &&
      windows_media_session_->HandleWindowMessage(message, wparam, lparam)) {
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
