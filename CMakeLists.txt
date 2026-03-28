cmake_minimum_required(VERSION 3.16)
project(rig LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUAJIT REQUIRED IMPORTED_TARGET luajit)

add_executable(rig
    src/main.c
)

target_link_libraries(rig PRIVATE PkgConfig::LUAJIT)

target_compile_options(rig PRIVATE
    $<$<C_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic>
)
