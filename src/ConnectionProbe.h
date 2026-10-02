// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

class QTcpSocket;

// Checks which remembered addresses are listening, with a plain TCP connect
// (no websocket handshake or password). The idea is from OBS Blade.
class ConnectionProbe : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // "host:port" -> reachable. Absent until the probe answers.
    Q_PROPERTY(QVariantMap reachable READ reachable NOTIFY reachableChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit ConnectionProbe(QObject *parent = nullptr);

    QVariantMap reachable() const { return m_reachable; }
    bool busy() const { return m_pending > 0; }

    static QString keyFor(const QString &host, int port);

public slots:
    // Entries are {host, port} maps. Replaces the previous results.
    void check(const QVariantList &addresses);

signals:
    void reachableChanged();
    void busyChanged();

private:
    void finish(const QString &key, bool ok, QTcpSocket *socket);

    QVariantMap m_reachable;
    int m_pending = 0;
    // Bumped on every check() so stale answers are dropped.
    quint64 m_generation = 0;
};
