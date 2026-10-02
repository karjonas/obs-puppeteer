// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include "MockObsServerQml.h"

#include <QJsonObject>

MockObsServerQml::MockObsServerQml(QObject *parent) : QObject(parent)
{
    connect(&m_server, &MockObsServer::clientConnected, &m_server,
            [this]() { m_server.sendHello(); });
    connect(&m_server, &MockObsServer::identifyReceived, &m_server,
            [this](const QJsonObject &) { m_server.sendIdentified(); });
    connect(&m_server, &MockObsServer::requestReceived, this,
            [this](const QString &requestType, const QString &requestId,
                   const QJsonObject &requestData) {
                emit requestReceived(requestType, requestId, requestData.toVariantMap());
            });
}

bool MockObsServerQml::start()
{
    const bool ok = m_server.start();
    if (ok)
        emit portChanged();
    return ok;
}

void MockObsServerQml::sendEvent(const QString &eventType, const QVariantMap &eventData)
{
    m_server.sendEvent(eventType, QJsonObject::fromVariantMap(eventData));
}

void MockObsServerQml::sendRequestResponse(const QString &requestId, bool ok,
                                           const QVariantMap &responseData)
{
    m_server.sendRequestResponse(requestId, ok, QJsonObject::fromVariantMap(responseData));
}
