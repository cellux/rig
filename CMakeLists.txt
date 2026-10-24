cmake_minimum_required(VERSION 3.16)
project(rig LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

enable_testing()

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUAJIT REQUIRED IMPORTED_TARGET luajit)
pkg_check_modules(SDL3 REQUIRED sdl3)
pkg_check_modules(FREETYPE2 REQUIRED freetype2)
pkg_check_modules(HARFBUZZ REQUIRED harfbuzz)
pkg_check_modules(LIBUV REQUIRED libuv)
find_program(LUAJIT_BIN NAMES luajit luajit-2.1 REQUIRED)

# JPEG decoding is optional: when libjpeg headers and library are present,
# jpeg.c compiles the real decoder; otherwise it compiles a stub that reports
# missing support at runtime.
find_package(JPEG)

include("${CMAKE_CURRENT_SOURCE_DIR}/src/modules/modules.cmake")

add_executable(rig
    src/main.c
    src/runtime.c
    ${MODULE_C_FILES}
    ${BYTECODE_SOURCES}
    "${MODULE_REGISTRY_C}"
)

set_target_properties(rig PROPERTIES
    ENABLE_EXPORTS ON
)

target_include_directories(rig PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    ${SDL3_INCLUDE_DIRS}
    ${FREETYPE2_INCLUDE_DIRS}
    ${HARFBUZZ_INCLUDE_DIRS}
    ${LIBUV_INCLUDE_DIRS}
)

target_link_libraries(rig PRIVATE
    PkgConfig::LUAJIT
    ${CMAKE_DL_LIBS}
)

if(JPEG_FOUND)
    target_compile_definitions(rig PRIVATE RIG_HAVE_JPEG=1)
    target_include_directories(rig PRIVATE ${JPEG_INCLUDE_DIRS})
    target_link_libraries(rig PRIVATE ${JPEG_LIBRARIES})
endif()

target_compile_options(rig PRIVATE
    ${SDL3_CFLAGS_OTHER}
    ${FREETYPE2_CFLAGS_OTHER}
    ${HARFBUZZ_CFLAGS_OTHER}
    ${LIBUV_CFLAGS_OTHER}
    $<$<C_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic>
)

add_test(
    NAME rig-tests
    COMMAND $<TARGET_FILE:rig> ${CMAKE_CURRENT_SOURCE_DIR}/scripts/run_all_tests.lua
)
set_tests_properties(rig-tests PROPERTIES
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    # Run the suite against SDL's headless video driver so graphics/frame tests
    # never flash a real window. The offscreen driver still provides OpenGL here;
    # tests that cannot get a backend skip themselves. Both hint spellings are set
    # for SDL2/SDL3 compatibility.
    ENVIRONMENT "SDL_VIDEO_DRIVER=offscreen;SDL_VIDEODRIVER=offscreen"
)
