#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

// The tray icon's notifications, and its menu items
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;

std::wstring Utf16FromUtf8(const std::string& s) {
  if (s.empty()) {
    return std::wstring();
  }
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      w.data(), n);
  return w;
}

template <typename T>
T Arg(const flutter::EncodableMap& args, const char* key, T fallback) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  const T* value = std::get_if<T>(&it->second);
  return value ? *value : fallback;
}

// Starting at login: a value in the user's Run key. Task Manager's Startup
// apps turns it off by marking it in StartupApproved instead (an odd first
// byte).
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupApprovedKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved"
    L"\\Run";
constexpr wchar_t kRunValue[] = L"Sippier";

bool LaunchesAtLogin() {
  if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_ANY, nullptr,
                   nullptr, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  BYTE approved[64];
  DWORD size = sizeof(approved);
  return RegGetValueW(HKEY_CURRENT_USER, kStartupApprovedKey, kRunValue,
                      RRF_RT_REG_BINARY, nullptr, approved,
                      &size) != ERROR_SUCCESS ||
         size == 0 || (approved[0] & 1) == 0;
}

// Runs this executable with --login, which keeps the window hidden.
void SetLaunchAtLogin(bool on) {
  if (on) {
    wchar_t exe[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring command = L"\"" + std::wstring(exe, n) + L"\" --login";
    RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, REG_SZ,
                    command.c_str(),
                    static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue);
  }
  // Else turning it off in Task Manager would outlast turning it on here
  RegDeleteKeyValueW(HKEY_CURRENT_USER, kStartupApprovedKey, kRunValue);
}

// An icon from the resources at the size for the window's DPI.
HICON LoadIconForDpi(HWND hwnd, int id, int metric) {
  int size = GetSystemMetricsForDpi(metric, GetDpiForWindow(hwnd));
  return static_cast<HICON>(LoadImageW(GetModuleHandle(nullptr),
                                       MAKEINTRESOURCEW(id), IMAGE_ICON, size,
                                       size, LR_DEFAULTCOLOR));
}

}  // namespace

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetUpChannel();
  SetWindowIcons();
  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
  AddTrayIcon();

  if (!start_hidden_) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  Shell_NotifyIconW(NIM_DELETE, &tray_);
  if (tray_icon_) {
    DestroyIcon(tray_icon_);
    tray_icon_ = nullptr;
  }
  channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetUpChannel() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "sippier/platform",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "startRinging") {
          // Windows may keep another app in front; the taskbar button
          // flashes then
          ShowAndActivate();
          FLASHWINFO flash{sizeof(flash), GetHandle(),
                           FLASHW_ALL | FLASHW_TIMERNOFG, 0, 0};
          FlashWindowEx(&flash);
          result->Success();
        } else if (method == "stopRinging") {
          FLASHWINFO flash{sizeof(flash), GetHandle(), FLASHW_STOP, 0, 0};
          FlashWindowEx(&flash);
          result->Success();
        } else if (method == "updateStatus") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            status_ = Utf16FromUtf8(Arg<std::string>(*args, "text", ""));
            registered_ = Arg<bool>(*args, "registered", false);
            std::string open = Arg<std::string>(*args, "openLabel", "");
            std::string quit = Arg<std::string>(*args, "quitLabel", "");
            if (!open.empty()) {
              open_label_ = Utf16FromUtf8(open);
            }
            if (!quit.empty()) {
              quit_label_ = Utf16FromUtf8(quit);
            }
            UpdateTrayIcon();
          }
          result->Success();
        } else if (method == "openUrl") {
          const auto* url = std::get_if<std::string>(call.arguments());
          if (url) {
            ShellExecuteW(nullptr, L"open", Utf16FromUtf8(*url).c_str(),
                          nullptr, nullptr, SW_SHOWNORMAL);
          }
          result->Success();
        } else if (method == "launchAtLogin") {
          result->Success(flutter::EncodableValue(LaunchesAtLogin()));
        } else if (method == "setLaunchAtLogin") {
          const auto* on = std::get_if<bool>(call.arguments());
          SetLaunchAtLogin(on && *on);
          result->Success(flutter::EncodableValue(LaunchesAtLogin()));
        } else {
          result->NotImplemented();
        }
      });
}

// The window class only has the large icon; Windows would scale it down for
// the title bar. Also at a new DPI.
void FlutterWindow::SetWindowIcons() {
  HWND hwnd = GetHandle();
  for (auto [type, metric] :
       {std::pair{ICON_SMALL, SM_CXSMICON}, std::pair{ICON_BIG, SM_CXICON}}) {
    HICON icon = LoadIconForDpi(hwnd, IDI_APP_ICON, metric);
    HICON old = reinterpret_cast<HICON>(SendMessageW(
        hwnd, WM_SETICON, type, reinterpret_cast<LPARAM>(icon)));
    if (old) {
      DestroyIcon(old);
    }
  }
}

// Also again after Explorer restarted.
void FlutterWindow::AddTrayIcon() {
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = 1;
  tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_.uCallbackMessage = kTrayMessage;
  HICON old = SetTrayIconAndTip();
  Shell_NotifyIconW(NIM_ADD, &tray_);
  if (old) {
    DestroyIcon(old);
  }

  // Clicks as NIN_SELECT, the menu key and right click as WM_CONTEXTMENU
  tray_.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &tray_);
}

void FlutterWindow::UpdateTrayIcon() {
  HICON old = SetTrayIconAndTip();
  Shell_NotifyIconW(NIM_MODIFY, &tray_);
  if (old) {
    DestroyIcon(old);
  }
}

// The mark in colour while an account is registered, in grey while none
// is, and the status as the tooltip. Returns the previous icon, to destroy
// once the shell has the new one.
HICON FlutterWindow::SetTrayIconAndTip() {
  HICON old = tray_icon_;
  tray_icon_ = LoadIconForDpi(GetHandle(),
                              registered_ ? IDI_TRAY_ON : IDI_TRAY_OFF,
                              SM_CXSMICON);
  tray_.hIcon = tray_icon_;
  std::wstring tip = L"Sippier: " + status_;
  wcsncpy_s(tray_.szTip, tip.c_str(), _TRUNCATE);
  return old;
}

void FlutterWindow::ShowTrayMenu() {
  // "&" would underline the next letter of an account's name
  std::wstring status;
  for (wchar_t c : status_) {
    status += c;
    if (c == L'&') {
      status += L'&';
    }
  }

  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, status.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuOpen, open_label_.c_str());
  AppendMenuW(menu, MF_STRING, kMenuQuit, quit_label_.c_str());
  SetMenuDefaultItem(menu, kMenuOpen, FALSE);

  // Only a menu of the foreground window closes on a click elsewhere
  HWND hwnd = GetHandle();
  SetForegroundWindow(hwnd);
  POINT pt;
  GetCursorPos(&pt);
  UINT align = GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                      : TPM_LEFTALIGN;
  UINT command = TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN |
                align,
      pt.x, pt.y, hwnd, nullptr);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (command == kMenuOpen) {
    ShowAndActivate();
  } else if (command == kMenuQuit) {
    Quit();
  }
}

void FlutterWindow::ShowAndActivate() {
  HWND hwnd = GetHandle();
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
}

// Closes for real. Flutter first asks the app (onExitRequested), which shuts
// the core down and so unregisters the accounts.
void FlutterWindow::Quit() {
  quitting_ = true;
  PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && !quitting_) {
    // Keeps running in the tray to take calls
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
        ShowAndActivate();
        break;
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        break;
    }
    return 0;
  }
  if (taskbar_created_ && message == taskbar_created_) {
    AddTrayIcon();
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
    case WM_DPICHANGED:
      SetWindowIcons();
      UpdateTrayIcon();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
