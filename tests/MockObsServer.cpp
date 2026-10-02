// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include "MockObsServer.h"

#include <QJsonDocument>

namespace {
constexpr int kOpHello = 0;
constexpr int kOpIdentify = 1;
constexpr int kOpIdentified = 2;
constexpr int kOpEvent = 5;
constexpr int kOpRequest = 6;
constexpr int kOpRequestResponse = 7;
} // namespace

MockObsServer::MockObsServer(QObject *parent)
    : QObject(parent),
      m_server(QStringLiteral("mock-obs-websocket"), QWebSocketServer::NonSecureMode)
{
    connect(&m_server, &QWebSocketServer::newConnection, this, &MockObsServer::onNewConnection);
}

bool MockObsServer::start()
{
    return m_server.listen(QHostAddress::LocalHost, 0);
}

quint16 MockObsServer::port() const
{
    return m_server.serverPort();
}

void MockObsServer::onNewConnection()
{
    m_client = m_server.nextPendingConnection();
    connect(m_client, &QWebSocket::textMessageReceived, this,
            &MockObsServer::onTextMessageReceived);
    emit clientConnected();
}

void MockObsServer::sendEnvelope(int op, const QJsonObject &d)
{
    if (!m_client)
        return;
    QJsonObject envelope;
    envelope[QStringLiteral("op")] = op;
    envelope[QStringLiteral("d")] = d;
    m_client->sendTextMessage(
            QString::fromUtf8(QJsonDocument(envelope).toJson(QJsonDocument::Compact)));
}

void MockObsServer::sendHello(const QJsonObject &authentication)
{
    QJsonObject d;
    d[QStringLiteral("obsWebSocketVersion")] = QStringLiteral("5.5.0");
    d[QStringLiteral("rpcVersion")] = 1;
    if (!authentication.isEmpty())
        d[QStringLiteral("authentication")] = authentication;
    sendEnvelope(kOpHello, d);
}

void MockObsServer::sendIdentified()
{
    QJsonObject d;
    d[QStringLiteral("negotiatedRpcVersion")] = 1;
    sendEnvelope(kOpIdentified, d);
}

void MockObsServer::sendEvent(const QString &eventType, const QJsonObject &eventData)
{
    QJsonObject d;
    d[QStringLiteral("eventType")] = eventType;
    d[QStringLiteral("eventIntent")] = 0;
    d[QStringLiteral("eventData")] = eventData;
    sendEnvelope(kOpEvent, d);
}

void MockObsServer::sendRequestResponse(const QString &requestId, bool ok,
                                        const QJsonObject &responseData, const QString &comment)
{
    QJsonObject status;
    status[QStringLiteral("result")] = ok;
    status[QStringLiteral("code")] = ok ? 100 : 300;
    if (!comment.isEmpty())
        status[QStringLiteral("comment")] = comment;

    QJsonObject d;
    d[QStringLiteral("requestId")] = requestId;
    d[QStringLiteral("requestStatus")] = status;
    if (!responseData.isEmpty())
        d[QStringLiteral("responseData")] = responseData;
    sendEnvelope(kOpRequestResponse, d);

    const auto it = m_unanswered.constFind(requestId);
    if (it != m_unanswered.cend()) {
        ++m_answered[*it];
        m_unanswered.erase(it);
    }
}

void MockObsServer::onTextMessageReceived(const QString &message)
{
    const QJsonObject root = QJsonDocument::fromJson(message.toUtf8()).object();
    const int op = root.value(QStringLiteral("op")).toInt(-1);
    const QJsonObject d = root.value(QStringLiteral("d")).toObject();

    if (op == kOpIdentify) {
        emit identifyReceived(d);
    } else if (op == kOpRequest) {
        const QString requestType = d.value(QStringLiteral("requestType")).toString();
        const QString requestId = d.value(QStringLiteral("requestId")).toString();
        // Recorded first: handlers usually answer from inside the signal.
        m_unanswered.insert(requestId, requestType);
        emit requestReceived(requestType, requestId,
                             d.value(QStringLiteral("requestData")).toObject());
    }
}
