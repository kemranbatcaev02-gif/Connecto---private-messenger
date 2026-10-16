#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Connecto is already running: bring its window to front instead of starting a second copy
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, L"Connecto.Messenger.SingleInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Connecto");
    if (existing != nullptr) {
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
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

  flutter::DartProject project(L"data");

  // Impeller on Windows (Flutter 3.47) grows memory with live animations and
  // video textures, so use the Skia renderer. Set CONNECTO_IMPELLER=on to compare.
  {
    wchar_t flag[16] = {0};
    const DWORD n = ::GetEnvironmentVariableW(L"CONNECTO_IMPELLER", flag, 16);
    const bool impeller = n > 0 && n < 16 && (flag[0] == L'o' || flag[0] == L'1');
    project.set_impeller_switch(impeller ? flutter::ImpellerSwitch::Enabled
                                         : flutter::ImpellerSwitch::Disabled);
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Окно 1200x780 по центру рабочей области (без панели задач). Window::Create
  // умножает размер и позицию на масштаб экрана, поэтому считаем в «логических»
  // пикселях — иначе при масштабе 125–150% окно вылезает за нижний край.
  RECT work{};
  if (!::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
    work = {0, 0, ::GetSystemMetrics(SM_CXSCREEN), ::GetSystemMetrics(SM_CYSCREEN)};
  }
  const HMONITOR monitor = ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int work_x = static_cast<int>(work.left / scale);
  const int work_y = static_cast<int>(work.top / scale);
  const int work_w = static_cast<int>((work.right - work.left) / scale);
  const int work_h = static_cast<int>((work.bottom - work.top) / scale);
  const int width = work_w - 40 < 1200 ? (work_w - 40 > 400 ? work_w - 40 : 400) : 1200;
  const int height = work_h - 40 < 780 ? (work_h - 40 > 600 ? work_h - 40 : 600) : 780;
  Win32Window::Point origin(work_x + (work_w > width ? (work_w - width) / 2 : 0),
                            work_y + (work_h > height ? (work_h - height) / 2 : 0));
  Win32Window::Size size(width, height);
  if (!window.Create(L"Connecto", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
