#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// Hosts the Flutter view. Closing the window hides it: Sippier keeps running
// in the notification area (tray) to take calls, and quits from the tray
// icon's menu. Through the "sippier/platform" channel the app sets the
// tray's status and brings the window up for an incoming call.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetUpChannel();
  void SetWindowIcons();
  void AddTrayIcon();
  void UpdateTrayIcon();
  HICON SetTrayIconAndTip();
  void ShowTrayMenu();
  void ShowAndActivate();
  void Quit();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  NOTIFYICONDATAW tray_{};
  HICON tray_icon_ = nullptr;
  std::wstring status_ = L"Starting\x2026";
  bool registered_ = false;
  // In the app's language once it sends its first status
  std::wstring open_label_ = L"Open Sippier";
  std::wstring quit_label_ = L"Quit Sippier";

  // Set by Quit, so WM_CLOSE closes instead of hiding.
  bool quitting_ = false;

  // Sent to top-level windows when Explorer (and its taskbar) restarts.
  UINT taskbar_created_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
