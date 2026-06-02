cmake_minimum_required(VERSION 3.20)
project(ftdi-winusb-rebind C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Static CRT so the exes are self-contained and CRT-consistent with libwdi.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# libwdi location — set on the command line or via CMakePresets.json.
set(LIBWDI_INCLUDE_DIR "" CACHE PATH     "Folder containing libwdi.h")
set(LIBWDI_LIB         "" CACHE FILEPATH "Path to libwdi.lib (static, /MT Release|x64)")

if(NOT LIBWDI_INCLUDE_DIR OR NOT LIBWDI_LIB)
    message(FATAL_ERROR
        "Set LIBWDI_INCLUDE_DIR and LIBWDI_LIB before configuring.\n"
        "Example:\n"
        "  cmake -S . -B build -G \"Visual Studio 17 2022\" -A x64 \\\n"
        "    -DLIBWDI_INCLUDE_DIR=C:/usr/local/src/libwdi/libwdi \\\n"
        "    -DLIBWDI_LIB=C:/usr/local/src/libwdi/x64/Release/lib/libwdi.lib")
endif()

# Phase 0: build-skeleton probe — prints the libwdi version to confirm the
# toolchain + static link are working before any real logic is added.
add_executable(ftdi-rebind-probe src/probe.c)
target_include_directories(ftdi-rebind-probe PRIVATE ${LIBWDI_INCLUDE_DIR})
target_link_libraries(ftdi-rebind-probe PRIVATE
    ${LIBWDI_LIB}
    setupapi cfgmgr32 ole32 newdev)
