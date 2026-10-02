# Copyright (C) 2026 Jonas Karlsson
# SPDX-License-Identifier: GPL-3.0-or-later

find_package(Qt6 REQUIRED COMPONENTS QuickTest Qml QuickControls2 WebSockets Network)

qt_add_executable(tst_qml_scenespanel
    main.cpp
    MockObsServerQml.h
    MockObsServerQml.cpp
    ${CMAKE_SOURCE_DIR}/tests/MockObsServer.h
    ${CMAKE_SOURCE_DIR}/tests/MockObsServer.cpp
)

target_include_directories(tst_qml_scenespanel PRIVATE ${CMAKE_SOURCE_DIR}/tests)

target_link_libraries(tst_qml_scenespanel
    PRIVATE
        obs-puppeteer-qml
        obs-puppeteer-qmlplugin
        Qt6::QuickTest
        Qt6::Qml
        Qt6::QuickControls2
        Qt6::WebSockets
        Qt6::Network
)

qt_import_qml_plugins(tst_qml_scenespanel)

target_compile_definitions(tst_qml_scenespanel PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

set(qml_test_environment
    "QT_QPA_PLATFORM=offscreen"
    "QT_ASSUME_STDERR_HAS_CONSOLE=1"
    "XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/test-config"
)
# On Windows the offscreen platform finds no fonts, so point it at the system
# fonts or text measures far too wide.
if(WIN32)
    file(TO_CMAKE_PATH "$ENV{WINDIR}/Fonts" windows_font_dir)
    list(APPEND qml_test_environment "QT_QPA_FONTDIR=${windows_font_dir}")
endif()

add_test(NAME ScenesPanelQmlTest COMMAND tst_qml_scenespanel)
set_tests_properties(ScenesPanelQmlTest PROPERTIES
    TIMEOUT 30
    ENVIRONMENT "${qml_test_environment}"
)
