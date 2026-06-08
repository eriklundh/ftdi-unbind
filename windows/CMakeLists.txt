cmake_minimum_required(VERSION 3.20)
project(ftdi-unbind-windows C)

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

# Research / developer executables — the Phase-0 probe and the unit/CLI test
# exes — are NOT part of a Release. They are excluded from the normal build
# (the default ALL target), so a plain `cmake --build` produces only the three
# shippable tools (ftdi-unbind, ftdi-bind, ftdi-doctor). Enable them for CI and
# local TDD with -DFTDI_BUILD_TESTS=ON. When enabled they are emitted to
# build/dev/ instead of build/<config>/, so they never sit next to the release
# exes — keeping the signing and packaging globs clean.
option(FTDI_BUILD_TESTS
    "Build the Phase-0 probe and unit/CLI test executables (not shipped)" OFF)
set(FTDI_DEV_BIN_DIR "${CMAKE_BINARY_DIR}/dev")

# Phase 0: build-skeleton probe — prints the libwdi version to confirm the
# toolchain + static link are working before any real logic is added.
if(FTDI_BUILD_TESTS)
    add_executable(ftdi-rebind-probe src/probe.c)
    target_include_directories(ftdi-rebind-probe PRIVATE ${LIBWDI_INCLUDE_DIR})
    target_link_libraries(ftdi-rebind-probe PRIVATE
        ${LIBWDI_LIB}
        setupapi cfgmgr32 ole32 newdev)
    set_target_properties(ftdi-rebind-probe PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${FTDI_DEV_BIN_DIR}")
endif()

# Phase 1: pure core — VID:PID matching, arg parsing.
# No libwdi, no Windows-driver APIs: the OBJECT library compiles with zero
# extra dependencies so unit tests run without admin or hardware.
add_library(ftdi_core OBJECT
    src/match.c
    src/args.c
    src/comdb.c)
target_include_directories(ftdi_core PUBLIC src)

if(FTDI_BUILD_TESTS)
    enable_testing()

    foreach(_test match args restore comdb)
        add_executable(test_${_test} tests/test_${_test}.c)
        target_link_libraries(test_${_test} PRIVATE ftdi_core)
        # /UNDEBUG keeps assert() active even in Release so CTest catches failures.
        target_compile_options(test_${_test} PRIVATE
            $<$<C_COMPILER_ID:MSVC>:/UNDEBUG>
            $<$<NOT:$<C_COMPILER_ID:MSVC>>:-UNDEBUG>)
        set_target_properties(test_${_test} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${FTDI_DEV_BIN_DIR}")
        add_test(NAME ${_test} COMMAND $<TARGET_FILE:test_${_test}>)
    endforeach()
endif()

# Phase 2: enum.c needs libwdi — kept in its own OBJECT lib so ftdi_core stays
# dep-free and unit tests remain buildable without admin or hardware.
add_library(ftdi_enum OBJECT src/enum.c)
target_include_directories(ftdi_enum PRIVATE src ${LIBWDI_INCLUDE_DIR})

# Elevation check — pure Win32, no libwdi; shared by rebind exes and doctor.
add_library(ftdi_elevate OBJECT src/elevate.c)
target_include_directories(ftdi_elevate PRIVATE src)

# Phase 3: WinUSB install — needs libwdi.
add_library(ftdi_install OBJECT src/install.c)
target_include_directories(ftdi_install PRIVATE src ${LIBWDI_INCLUDE_DIR})

# Phase 4: VCP restore — SetupAPI/CfgMgr32/newdev; no libwdi.
# Depends on ftdi_core for hwid_matches_vidpid.
add_library(ftdi_restore OBJECT src/restore.c)
target_include_directories(ftdi_restore PRIVATE src)

# Phase 4: two exes built from the same main.c; ACTION_THIS selects direction.
set(_rebind_libs
    ftdi_core ftdi_elevate ftdi_enum ftdi_install ftdi_restore
    ${LIBWDI_LIB} setupapi cfgmgr32 ole32 newdev)

add_executable(ftdi-unbind src/main.c)
target_compile_definitions(ftdi-unbind PRIVATE ACTION_THIS=ACTION_UNBIND)
target_include_directories(ftdi-unbind PRIVATE src ${LIBWDI_INCLUDE_DIR})
target_link_libraries(ftdi-unbind PRIVATE ${_rebind_libs})

add_executable(ftdi-bind src/main.c)
target_compile_definitions(ftdi-bind PRIVATE ACTION_THIS=ACTION_BIND)
target_include_directories(ftdi-bind PRIVATE src ${LIBWDI_INCLUDE_DIR})
target_link_libraries(ftdi-bind PRIVATE ${_rebind_libs})

# Phase 5: ftdi-doctor — ComDB + driver store repair; no libwdi.
add_library(ftdi_comdb_win OBJECT src/comdb_win.c)
target_include_directories(ftdi_comdb_win PRIVATE src)

add_executable(ftdi-doctor src/doctor_main.c)
target_include_directories(ftdi-doctor PRIVATE src)
target_link_libraries(ftdi-doctor PRIVATE
    ftdi_core ftdi_elevate ftdi_comdb_win
    setupapi cfgmgr32)

# Phase 6: CLI exit-code parity tests — spawn each exe and check the exit code.
# Exe paths injected via compile definitions so the test is device- and admin-free.
if(FTDI_BUILD_TESTS)
    add_executable(test_cli tests/test_cli.c)
    target_compile_definitions(test_cli PRIVATE
        UNBIND_EXE="$<TARGET_FILE:ftdi-unbind>"
        BIND_EXE="$<TARGET_FILE:ftdi-bind>"
        DOCTOR_EXE="$<TARGET_FILE:ftdi-doctor>")
    target_compile_options(test_cli PRIVATE
        $<$<C_COMPILER_ID:MSVC>:/UNDEBUG>
        $<$<NOT:$<C_COMPILER_ID:MSVC>>:-UNDEBUG>)
    set_target_properties(test_cli PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${FTDI_DEV_BIN_DIR}")
    add_dependencies(test_cli ftdi-unbind ftdi-bind ftdi-doctor)
    add_test(NAME cli COMMAND $<TARGET_FILE:test_cli>)
endif()
