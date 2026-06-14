cmake_minimum_required(VERSION 3.14)
project(typst_flutter LANGUAGES CXX)

# Tell Flutter to bundle the pre-built DLL into the Windows application
set(typst_flutter_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../.typst_flutter_prebuilt/windows/typst_flutter.dll"
  PARENT_SCOPE
)
