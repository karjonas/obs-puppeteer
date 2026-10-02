// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include "ConnectionProbe.h"

#include <QTcpSocket>
#include <QTimer>

namespace {
constexpr int kProbeTimeoutMs = 1500;
} // namespace

ConnectionProbe::ConnectionProbe(QObject *parent) : QObject(parent) { }

QString ConnectionProbe::keyFor(const QString &host, int port)
{
    return QStringLiteral("%1:%2").arg(host).arg(port);
}

void ConnectionProbe::check(const QVariantList &addresses)
{
    ++m_generation;
    const quint64 generation = m_generation;

    m_reachable.clear();
    m_pending = 0;

    for (const QVariant &entry : addresses) {
        const QVariantMap address = entry.toMap();
        const QString host = address.value(QStringLiteral("host")).toString();
        const int port = address.value(QStringLiteral("port")).toInt();
        if (host.isEmpty() || port <= 0)
            continue;

        const QString key = keyFor(host, port);
        ++m_pending;

        auto *socket = new QTcpSocket(this);
        auto *timeout = new QTimer(socket);
        timeout->setSingleShot(true);
        timeout->setInterval(kProbeTimeoutMs);

        // The first of the three signals wins.
        connect(socket, &QTcpSocket::connected, this, [this, key, socket, generation]() {
            if (generation == m_generation)
                finish(key, true, socket);
            else
                socket->deleteLater();
        });
        connect(socket, &QTcpSocket::errorOccurred, this, [this, key, socket, generation]() {
            if (generation == m_generation)
                finish(key, false, socket);
            else
                socket->deleteLater();
        });
        connect(timeout, &QTimer::timeout, this, [this, key, socket, generation]() {
            if (generation == m_generation)
                finish(key, false, socket);
            else
                socket->deleteLater();
        });

        timeout->start();
        socket->connectToHost(host, quint16(port));
    }

    emit reachableChanged();
    emit busyChanged();
}

void ConnectionProbe::finish(const QString &key, bool ok, QTcpSocket *socket)
{
    // The socket can report more than once; the first answer counts.
    if (m_reachable.contains(key)) {
        socket->deleteLater();
        return;
    }

    socket->abort();
    socket->deleteLater();

    m_reachable[key] = ok;
    emit reachableChanged();

    if (--m_pending <= 0) {
        m_pending = 0;
        emit busyChanged();
    }
}
