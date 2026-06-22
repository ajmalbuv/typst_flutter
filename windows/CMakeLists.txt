cmake_minimum_required(VERSION 3.14)
project(typst_flutter LANGUAGES CXX)

# ── Pre-built binary detection ─────────────────────────────────────────────────
#
# The pre-built DLL is placed by `dart run typst_flutter:setup` at:
#   <package_root>/.typst_flutter_prebuilt/windows/typst_flutter.dll
#
# CMAKE_CURRENT_SOURCE_DIR is the plugin's windows/ directory (may be inside
# the pub cache). The consumer app root is two levels up from there:
#   <pub_cache>/typst_flutter-x.y.z/windows/ → ../../ → consumer app root
# (or for a local path dep: <repo>/windows/ → ../../ → consumer app root)
#
# IMPORTANT: `dart run typst_flutter:setup` MUST be run from the consumer app
# root (where pubspec.yaml lives). Running it from inside the pub cache fails
# with "Cannot operate on packages inside the cache."
# The setup script resolves the package URI internally and deposits the binary
# into the correct pub-cache package directory regardless.

set(_prebuilt_dll
  "${CMAKE_CURRENT_SOURCE_DIR}/../.typst_flutter_prebuilt/windows/typst_flutter.dll"
)

if(NOT EXISTS "${_prebuilt_dll}")
  message(STATUS "typst_flutter: prebuilt binary missing — running setup...")

  # Consumer app root = one level above the app's windows/ folder (CMAKE_SOURCE_DIR)
  set(_app_root "${CMAKE_SOURCE_DIR}/..")

  execute_process(
    COMMAND cmd /c dart run typst_flutter:setup
    WORKING_DIRECTORY "${_app_root}"
    RESULT_VARIABLE _setup_result
    OUTPUT_VARIABLE _setup_out
    ERROR_VARIABLE  _setup_err
  )

  if(NOT _setup_result EQUAL 0)
    message(WARNING
      "typst_flutter: auto-download failed (exit ${_setup_result}).\n"
      "  stdout: ${_setup_out}\n"
      "  stderr: ${_setup_err}\n"
      "  Run manually: dart run typst_flutter:setup"
    )
  endif()
endif()

if(NOT EXISTS "${_prebuilt_dll}")
  message(FATAL_ERROR
    "typst_flutter: typst_flutter.dll not found at:\n"
    "  ${_prebuilt_dll}\n\n"
    "Run once from your app root:\n"
    "  dart run typst_flutter:setup\n"
  )
endif()

# Tell Flutter to bundle the pre-built DLL into the Windows application
set(typst_flutter_bundled_libraries
  "${_prebuilt_dll}"
  PARENT_SCOPE
)
