cmake_minimum_required(VERSION 3.14)
project(typst_flutter LANGUAGES CXX)

# Tell Flutter to bundle the pre-built SO into the Linux application
set(typst_flutter_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../.typst_flutter_prebuilt/linux/libtypst_flutter.so"
  PARENT_SCOPE
)
