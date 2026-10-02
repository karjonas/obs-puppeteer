// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QObject>
#include <QQmlEngine>
#include <QSysInfo>

// Information for the About dialog that QML can't get by itself. The app
// version is Qt.application.version, set in main().
class AppInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Runtime and build-time Qt versions, which can differ.
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(QString qtBuildVersion READ qtBuildVersion CONSTANT)
    // OS and Qt platform plugin (e.g. wayland or xcb).
    Q_PROPERTY(QString platform READ platform CONSTANT)

public:
    explicit AppInfo(QObject *parent = nullptr) : QObject(parent) { }

    QString qtVersion() const { return QString::fromLatin1(qVersion()); }
    QString qtBuildVersion() const { return QStringLiteral(QT_VERSION_STR); }

    QString platform() const
    {
        return QStringLiteral("%1, %2").arg(QSysInfo::prettyProductName(),
                                            QGuiApplication::platformName());
    }

    // By SPDX identifier, from the texts compiled into :/licenses/ (see
    // CMakeLists.txt). Empty for one that isn't there.
    Q_INVOKABLE QString licenseText(const QString &spdxId) const
    {
        QFile file(QStringLiteral(":/licenses/%1.txt").arg(spdxId));
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            return { };
        return QString::fromUtf8(file.readAll());
    }

    Q_INVOKABLE void copyToClipboard(const QString &text) const
    {
        QGuiApplication::clipboard()->setText(text);
    }
};
