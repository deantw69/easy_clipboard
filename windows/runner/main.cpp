#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 單一實例:若程式已在執行(可能正縮小在系統匣),就請既有實例把視窗叫回來,
  // 然後本次啟動安靜結束 —— 避免再開一個視窗閃一下又關掉。
  // 這個判斷在建立任何視窗之前完成,所以第二次點捷徑/工作列不會有任何閃爍。
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, L"SyncNest_SingleInstance_Mutex");
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    UINT show_msg =
        ::RegisterWindowMessageW(L"SYNCNEST_SHOW_FIRST_INSTANCE");
    // 允許既有實例把自己帶到前景(否則只會閃工作列圖示)。
    ::AllowSetForegroundWindow(ASFW_ANY);
    ::PostMessage(HWND_BROADCAST, show_msg, 0, 0);
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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SyncNest", origin, size)) {
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
