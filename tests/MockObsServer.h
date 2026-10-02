// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QWebSocketServer>
#include <QWebSocket>
#include <QJsonObject>
#include <QHash>

// A minimal obs-websocket server for testing ObsClient without OBS.
class MockObsServer : public QObject
{
    Q_OBJECT

public:
    explicit MockObsServer(QObject *parent = nullptr);

    bool start();
    quint16 port() const;

    QWebSocket *clientSocket() const { return m_client; }

    void sendHello(const QJsonObject &authentication = { });
    void sendIdentified();
    void sendEvent(const QString &eventType, const QJsonObject &eventData);
    void sendRequestResponse(const QString &requestId, bool ok,
                             const QJsonObject &responseData = { }, const QString &comment = { });

    // Requests of this type answered so far. Before sending an event, wait on
    // this for any request whose answer would overwrite it; the client's value
    // may already match before the answer arrives.
    int answeredCount(const QString &requestType) const { return m_answered.value(requestType); }

signals:
    void clientConnected();
    void identifyReceived(const QJsonObject &d);
    void requestReceived(const QString &requestType, const QString &requestId,
                         const QJsonObject &requestData);

private slots:
    void onNewConnection();
    void onTextMessageReceived(const QString &message);

private:
    void sendEnvelope(int op, const QJsonObject &d);

    QWebSocketServer m_server;
    QWebSocket *m_client = nullptr;
    // requestId -> requestType for requests not answered yet.
    QHash<QString, QString> m_unanswered;
    QHash<QString, int> m_answered;
};
