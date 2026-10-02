# Copyright (C) 2026 Jonas Karlsson
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.21)
project(obs-puppeteer VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Svg isn't used from code, but its image format plugin is what loads the SVG
# icons; without it they silently don't render.
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Svg WebSockets)

# 6.8 for Popup.popupType, which the popups set to Popup.Item so they stay drawn
# in the window if Qt's default changes. Most of the code would work with 6.5.
qt_standard_project_setup(REQUIRES 6.8)

if(WIN32)
    # Generated, so the exe's version metadata comes from project().
    configure_file(resources/win/app.rc.in "${CMAKE_CURRENT_BINARY_DIR}/app.rc" @ONLY)
    set(APP_ICON_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/app.rc")
endif()

# A static library, so the QML tests can import the same module.
qt_add_library(obs-puppeteer-qml STATIC)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Icons.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# Short, stable resource paths for the icons; Icons.qml refers to them.
foreach(icon audio mute visible invisible close)
    set_source_files_properties(resources/icons/obs/${icon}.svg
        PROPERTIES QT_RESOURCE_ALIAS icons/${icon}.svg)
endforeach()
set_source_files_properties(resources/icons/obs-puppeteer.svg
    PROPERTIES QT_RESOURCE_ALIAS icons/obs-puppeteer.svg)

qt_add_qml_module(obs-puppeteer-qml
    URI OBSPuppeteer
    VERSION 1.0
    # Put qmldir under OBSPuppeteer/, where qmllint expects it.
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/OBSPuppeteer
    RESOURCES
        resources/icons/obs/audio.svg
        resources/icons/obs/mute.svg
        resources/icons/obs/visible.svg
        resources/icons/obs/invisible.svg
        resources/icons/obs/close.svg
        resources/icons/obs-puppeteer.svg
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/Icons.qml
        qml/Panel.qml
        qml/ObsButton.qml
        qml/ObsComboBox.qml
        qml/ObsToggleSwitch.qml
        qml/ObsScrollBar.qml
        qml/ObsHostField.qml
        qml/ConnectionView.qml
        qml/ThumbnailImage.qml
        qml/LevelMeter.qml
        qml/MeterScale.qml
        qml/ScenesPanel.qml
        qml/SourcesPanel.qml
        qml/AudioPanel.qml
        qml/StatusBar.qml
        qml/TransitionBar.qml
        qml/AboutDialog.qml
    SOURCES
        src/ObsClient.h
        src/ObsClient.cpp
        src/ConnectionProbe.h
        src/SystemFonts.h
        src/AppInfo.h
        src/ConnectionProbe.cpp
)

target_include_directories(obs-puppeteer-qml
    PUBLIC
        src
)

target_link_libraries(obs-puppeteer-qml
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Svg
        Qt6::WebSockets
)

# The licence texts shown in the About dialog, compiled in so every build
# carries them. Aliased to sit together under :/licenses/; the LGPL lives
# outside LICENSES/ because no file in the repository is under it.
set_source_files_properties(LICENSES/GPL-3.0-or-later.txt
    PROPERTIES QT_RESOURCE_ALIAS GPL-3.0-or-later.txt)
set_source_files_properties(resources/licenses/LGPL-3.0-or-later.txt
    PROPERTIES QT_RESOURCE_ALIAS LGPL-3.0-or-later.txt)
qt_add_resources(obs-puppeteer-qml "licenses"
    PREFIX /licenses
    FILES
        LICENSES/GPL-3.0-or-later.txt
        resources/licenses/LGPL-3.0-or-later.txt
)

qt_add_executable(obs-puppeteer
    src/main.cpp
    ${APP_ICON_RESOURCE}
)

# The version is project()'s plus the git tag and hash, generated on every
# build by cmake/Version.cmake.
set(version_header "${CMAKE_CURRENT_BINARY_DIR}/generated/Version.h")
add_custom_target(obs-puppeteer-version
    COMMAND "${CMAKE_COMMAND}"
        -DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -DOUTPUT=${version_header}
        -DPROJECT_VERSION=${PROJECT_VERSION}
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Version.cmake"
    BYPRODUCTS "${version_header}"
    COMMENT "Reading the version from git"
    VERBATIM
)
add_dependencies(obs-puppeteer obs-puppeteer-version)
target_include_directories(obs-puppeteer PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")

target_link_libraries(obs-puppeteer PRIVATE obs-puppeteer-qml obs-puppeteer-qmlplugin)

# Links the QML plugins in static Qt builds; a no-op otherwise.
qt_import_qml_plugins(obs-puppeteer)

set_target_properties(obs-puppeteer PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

install(TARGETS obs-puppeteer
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)

if(UNIX AND NOT APPLE)
    install(FILES resources/obs-puppeteer.desktop DESTINATION share/applications)
    install(FILES resources/io.github.karjonas.obs_puppeteer.appdata.xml
        DESTINATION share/metainfo
    )
    install(FILES resources/icons/obs-puppeteer.png
        DESTINATION share/icons/hicolor/256x256/apps
        RENAME obs-puppeteer.png
    )
    # The PNG is rendered from this SVG.
    install(FILES resources/icons/obs-puppeteer.svg
        DESTINATION share/icons/hicolor/scalable/apps
        RENAME obs-puppeteer.svg
    )
endif()

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
