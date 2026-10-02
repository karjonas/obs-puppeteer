// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>

#include "MockObsServer.h"

// QML wrapper around MockObsServer for Qt Quick Tests. Completes the handshake
// automatically; bad handshakes are covered by tst_ObsClient.
class MockObsServerQml : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int port READ port NOTIFY portChanged)

public:
    explicit MockObsServerQml(QObject *parent = nullptr);

    int port() const { return m_server.port(); }

    Q_INVOKABLE bool start();
    Q_INVOKABLE void sendEvent(const QString &eventType, const QVariantMap &eventData);
    Q_INVOKABLE void sendRequestResponse(const QString &requestId, bool ok,
                                         const QVariantMap &responseData);
    // See MockObsServer::answeredCount.
    Q_INVOKABLE int answeredCount(const QString &requestType) const
    {
        return m_server.answeredCount(requestType);
    }

signals:
    void portChanged();
    void requestReceived(const QString &requestType, const QString &requestId,
                         const QVariantMap &requestData);

private:
    MockObsServer m_server;
};
