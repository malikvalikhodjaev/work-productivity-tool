#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
#ifdef IW_FOCUS_EDITION
constexpr wchar_t kAppId[] = L"UzIW.FocusNorms";
#else
// A stable native-shell identity, separate from the former web/legacy pin.
constexpr wchar_t kAppId[] = L"UzIW.IndicatorsWork.Desktop";
#endif

// Windows uses these properties when a running window is pinned afresh.
void ConfigureTaskbar(HWND window, const wchar_t* title) {
  wchar_t executable[32768];
  const DWORD length = GetModuleFileNameW(nullptr, executable, 32768);
  if (!length || length >= 32768) return;
  std::wstring path(executable, length);
  const auto directory = path.substr(0, path.find_last_of(L"\\/"));
#ifdef IW_ICON_HASH
  const std::string icon_name = "pomodoro-club-desktop-" IW_ICON_HASH ".ico";
  auto icon_file = directory + L"\\" + std::wstring(icon_name.begin(), icon_name.end());
#else
  auto icon_file = directory + L"\\data\\flutter_assets\\assets\\iw.ico";
#endif
  if (GetFileAttributesW(icon_file.c_str()) == INVALID_FILE_ATTRIBUTES) {
    icon_file = directory + L"\\data\\flutter_assets\\assets\\iw.ico";
  }
  const auto icon = icon_file + L",0";
  // Own both HICONs for the lifetime of this single application window.
  // WM_SETICON also tells the taskbar to redraw an existing running button.
  static HICON small_icon = nullptr;
  static HICON large_icon = nullptr;
  const UINT dpi = GetDpiForWindow(window);
  if (!small_icon) small_icon = static_cast<HICON>(LoadImageW(nullptr,
      icon_file.c_str(), IMAGE_ICON, GetSystemMetricsForDpi(SM_CXSMICON, dpi),
      GetSystemMetricsForDpi(SM_CYSMICON, dpi), LR_LOADFROMFILE));
  if (!large_icon) large_icon = static_cast<HICON>(LoadImageW(nullptr,
      icon_file.c_str(), IMAGE_ICON, GetSystemMetricsForDpi(SM_CXICON, dpi),
      GetSystemMetricsForDpi(SM_CYICON, dpi), LR_LOADFROMFILE));
  if (small_icon) SendMessageW(window, WM_SETICON, ICON_SMALL,
      reinterpret_cast<LPARAM>(small_icon));
  if (large_icon) SendMessageW(window, WM_SETICON, ICON_BIG,
      reinterpret_cast<LPARAM>(large_icon));
  const auto command = L"\"" + path + L"\"";
  IPropertyStore* properties = nullptr;
  if (FAILED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&properties)))) return;
  const auto set = [&](const PROPERTYKEY& key, const wchar_t* value) {
    PROPVARIANT property;
    if (SUCCEEDED(InitPropVariantFromString(value, &property))) {
      properties->SetValue(key, property);
      PropVariantClear(&property);
    }
  };
  set(PKEY_AppUserModel_RelaunchCommand, command.c_str());
  set(PKEY_AppUserModel_RelaunchDisplayNameResource, title);
  set(PKEY_AppUserModel_RelaunchIconResource, icon.c_str());
  set(PKEY_AppUserModel_ID, kAppId);
  properties->Commit();
  properties->Release();
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
#ifdef IW_FOCUS_EDITION
  const wchar_t* client_mutex = L"Local\\FocusNormsNativeClient";
  const wchar_t* client_title = L"Focus & Norms";
#else
  const wchar_t* client_mutex = L"Local\\IndicatorsWorkNativeClient";
  const wchar_t* client_title = L"Indicators & Work Dashboard";
#endif
  HANDLE single_instance = ::CreateMutexW(nullptr, FALSE, client_mutex);
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", client_title);
    if (existing) { ::ShowWindow(existing, SW_RESTORE); ::SetForegroundWindow(existing); }
    if (single_instance) ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetCurrentProcessExplicitAppUserModelID(kAppId);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(client_title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  ConfigureTaskbar(window.GetHandle(), client_title);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance) ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
