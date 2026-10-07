# Copyright (C) 2026 Jonas Karlsson
# SPDX-License-Identifier: GPL-3.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Test Core Network Qml WebSockets)

qt_add_executable(tst_ObsClient
    tst_ObsClient.cpp
    MockObsServer.h
    MockObsServer.cpp
    ${CMAKE_SOURCE_DIR}/src/ObsClient.h
    ${CMAKE_SOURCE_DIR}/src/ObsClient.cpp
    ${CMAKE_SOURCE_DIR}/src/ConnectionProbe.h
    ${CMAKE_SOURCE_DIR}/src/ConnectionProbe.cpp
)

target_include_directories(tst_ObsClient PRIVATE ${CMAKE_SOURCE_DIR}/src)

target_link_libraries(tst_ObsClient
    PRIVATE
        Qt6::Test
        Qt6::Core
        Qt6::Network
        Qt6::Qml
        Qt6::WebSockets
)

add_test(NAME ObsClientTest COMMAND tst_ObsClient)
# Generous: the limit only guards against a hung test, and refused connections
# take seconds on Windows.
set_tests_properties(ObsClientTest PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_ASSUME_STDERR_HAS_CONSOLE=1"
)

add_subdirectory(qml)
