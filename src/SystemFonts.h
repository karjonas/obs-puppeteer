// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QFontDatabase>

// The system's fixed-width font family, which QML can't query portably.
class SystemFonts : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString fixedFamily READ fixedFamily CONSTANT)

public:
    explicit SystemFonts(QObject *parent = nullptr) : QObject(parent) { }

    QString fixedFamily() const
    {
        return QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
    }
};
