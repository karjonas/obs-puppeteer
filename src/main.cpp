// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QCommandLineParser>
#include <QIcon>

#include "Version.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    // The internal names decide where settings are stored, so they're kept
    // lowercase and space-free; the display name is what users see.
    app.setOrganizationName(QStringLiteral("obs-puppeteer"));
    app.setOrganizationDomain(QStringLiteral("karjonas.github.io"));
    app.setApplicationName(QStringLiteral("obs-puppeteer"));
    app.setApplicationDisplayName(QStringLiteral("OBS Puppeteer"));
    // Matches resources/obs-puppeteer.desktop, so Wayland desktops can pair the
    // window with its icon and name.
    QGuiApplication::setDesktopFileName(QStringLiteral("obs-puppeteer"));
    // Generated at build time from git; see cmake/Version.cmake.
    app.setApplicationVersion(QStringLiteral(OBS_PUPPETEER_VERSION));

    // Set explicitly: the colours in Theme.qml assume Material.
    QQuickStyle::setStyle(QStringLiteral("Material"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Unofficial control panel for OBS Studio"));
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption hostOption(QStringLiteral("host"),
                                  QStringLiteral("obs-websocket host to auto-connect to"),
                                  QStringLiteral("host"));
    QCommandLineOption portOption(QStringLiteral("port"), QStringLiteral("obs-websocket port"),
                                  QStringLiteral("port"), QStringLiteral("4455"));
    QCommandLineOption passwordOption(QStringLiteral("password"),
                                      QStringLiteral("obs-websocket password"),
                                      QStringLiteral("password"));
    parser.addOption(hostOption);
    parser.addOption(portOption);
    parser.addOption(passwordOption);
    parser.process(app);

    QQmlApplicationEngine engine;
    // Initial properties rather than context properties, so the QML compiler and
    // qmllint can see them.
    engine.setInitialProperties({
            { QStringLiteral("cliHost"), parser.value(hostOption) },
            { QStringLiteral("cliPort"), parser.value(portOption).toInt() },
            { QStringLiteral("cliPassword"), parser.value(passwordOption) },
    });

    QObject::connect(
            &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
            []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.loadFromModule("OBSPuppeteer", "Main");

    return app.exec();
}
