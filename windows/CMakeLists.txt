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

# Phase 1: pure core — VID:PID matching, arg parsing.
# No libwdi, no Windows-driver APIs: the OBJECT library compiles with zero
# extra dependencies so unit tests run without admin or hardware.
add_library(ftdi_core OBJECT
    src/match.c
    src/args.c)
target_include_directories(ftdi_core PUBLIC src)

enable_testing()

foreach(_test match args restore)
    add_executable(test_${_test} tests/test_${_test}.c)
    target_link_libraries(test_${_test} PRIVATE ftdi_core)
    # /UNDEBUG keeps assert() active even in Release so CTest catches failures.
    target_compile_options(test_${_test} PRIVATE
        $<$<C_COMPILER_ID:MSVC>:/UNDEBUG>
        $<$<NOT:$<C_COMPILER_ID:MSVC>>:-UNDEBUG>)
    add_test(NAME ${_test} COMMAND $<TARGET_FILE:test_${_test}>)
endforeach()

# Phase 2: enum.c needs libwdi — kept in its own OBJECT lib so ftdi_core stays
# dep-free and unit tests remain buildable without admin or hardware.
add_library(ftdi_enum OBJECT src/enum.c)
target_include_directories(ftdi_enum PRIVATE src ${LIBWDI_INCLUDE_DIR})

# Phase 3: elevation check + WinUSB install — needs Win32/libwdi but not the
# pure core, so it lives in its own OBJECT lib.
add_library(ftdi_install OBJECT
    src/elevate.c
    src/install.c)
target_include_directories(ftdi_install PRIVATE src ${LIBWDI_INCLUDE_DIR})

# Phase 4: VCP restore — SetupAPI/CfgMgr32/newdev; no libwdi.
# Depends on ftdi_core for hwid_matches_vidpid.
add_library(ftdi_restore OBJECT src/restore.c)
target_include_directories(ftdi_restore PRIVATE src)

# Phase 4: two exes built from the same main.c; ACTION_THIS selects direction.
set(_rebind_libs
    ftdi_core ftdi_enum ftdi_install ftdi_restore
    ${LIBWDI_LIB} setupapi cfgmgr32 ole32 newdev)

add_executable(ftdi-unbind src/main.c)
target_compile_definitions(ftdi-unbind PRIVATE ACTION_THIS=ACTION_UNBIND)
target_include_directories(ftdi-unbind PRIVATE src ${LIBWDI_INCLUDE_DIR})
target_link_libraries(ftdi-unbind PRIVATE ${_rebind_libs})

add_executable(ftdi-bind src/main.c)
target_compile_definitions(ftdi-bind PRIVATE ACTION_THIS=ACTION_BIND)
target_include_directories(ftdi-bind PRIVATE src ${LIBWDI_INCLUDE_DIR})
target_link_libraries(ftdi-bind PRIVATE ${_rebind_libs})
