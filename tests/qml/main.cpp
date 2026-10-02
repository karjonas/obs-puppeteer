// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include <QtQuickTest/quicktest.h>
#include <QQmlEngine>
#include <QCoreApplication>
#include <QQuickStyle>

#include "MockObsServerQml.h"

class Setup : public QObject
{
    Q_OBJECT

public slots:
    // The app's style; platform defaults (e.g. Windows' native style) ignore the
    // customised controls.
    void applicationAvailable() { QQuickStyle::setStyle(QStringLiteral("Material")); }

    void qmlEngineAvailable(QQmlEngine *)
    {
        qmlRegisterType<MockObsServerQml>("ObsPuppeteerTest", 1, 0, "MockObsServerQml");

        // Settings needs these to find its file. XDG_CONFIG_HOME points at the build
        // directory, so tests never touch the real config.
        QCoreApplication::setOrganizationName(QStringLiteral("obs-puppeteer"));
        QCoreApplication::setApplicationName(QStringLiteral("obs-puppeteer-tests"));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(obs_puppeteer_qml_tests, Setup)

#include "main.moc"
