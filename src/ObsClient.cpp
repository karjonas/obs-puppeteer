// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include "ObsClient.h"

#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QUrl>
#include <QUuid>
#include <QDateTime>
#include <QDebug>

#include <cmath>

namespace {
// obs-websocket 5.x opcodes (docs/generated/protocol.md)
constexpr int kOpHello = 0;
constexpr int kOpIdentify = 1;
constexpr int kOpIdentified = 2;
constexpr int kOpEvent = 5;
constexpr int kOpRequest = 6;
constexpr int kOpRequestResponse = 7;

// EventSubscription::All
constexpr int kEventSubscriptionAll = 2047;
// Not included in All: high-volume events (~20/s) must be requested by name.
constexpr int kEventSubscriptionInputVolumeMeters = 1 << 16;

constexpr int kRpcVersion = 1;
constexpr int kReconnectDelayMs = 3000;
// WebSocketCloseCode::AuthenticationFailed
constexpr int kCloseAuthenticationFailed = 4009;
constexpr int kStatusPollIntervalMs = 1000;
// Program (and preview) thumbnails refresh every tick; the other scenes one at
// a time in round-robin, every Nth tick, so the grid doesn't flicker.
constexpr int kPreviewPollIntervalMs = 500;
constexpr int kBackgroundRefreshEveryNTicks = 10;
// Thumbnail widths; the height follows the canvas aspect. The UI sets
// previewWidth and the setter clamps it to these, since OBS encodes every
// requested pixel.
constexpr int kDefaultPreviewWidth = 240;
constexpr int kMinPreviewWidth = 160;
constexpr int kMaxPreviewWidth = 1280;
// Height cap, for vertical canvases where the height derived from the width
// would be far larger.
constexpr int kMaxPreviewHeight = 1280;
// Widths snap to this step so resizing the window requests only a few sizes.
constexpr int kPreviewWidthStep = 80;
constexpr int kPreviewCompressionQuality = 75;

// Meter behaviour follows OBS's frontend/components/VolumeMeter.cpp defaults.
constexpr qreal kMeterFloorDb = -60.0;
// 20 dB / 1.7 s, applied against elapsed time as OBS does.
constexpr qreal kMeterPeakDecayDbPerSecond = 11.76;
// Each channel is [magnitude, peak, inputPeak]; inputPeak (pre-fader) is unused.
constexpr int kMeterMagnitudeIndex = 0;
constexpr int kMeterPeakIndex = 1;
// OBS's magnitudeIntegrationTime: 99% of the way to a new value in 300 ms.
constexpr qreal kMagnitudeIntegrationSec = 0.3;
// Smaller changes are under a pixel, so the UI isn't notified.
constexpr qreal kMeterEpsilon = 0.002;

// Linear multiplier to a 0..1 fraction of OBS's -60..0 dB meter scale.
qreal levelFractionFromMultiplier(qreal multiplier)
{
    if (multiplier <= 0.0)
        return 0.0;
    const qreal db = 20.0 * std::log10(multiplier);
    return qBound(0.0, (db - kMeterFloorDb) / -kMeterFloorDb, 1.0);
}

bool isLikelyAudioInputKind(const QString &kind)
{
    static const QStringList audioMarkers = {
        QStringLiteral("input_capture"), QStringLiteral("output_capture"), QStringLiteral("wasapi"),
        QStringLiteral("pulse"),         QStringLiteral("coreaudio"),      QStringLiteral("alsa"),
        QStringLiteral("audio_line"),
    };
    for (const auto &marker : audioMarkers) {
        if (kind.contains(marker, Qt::CaseInsensitive))
            return true;
    }
    return false;
}
} // namespace

ObsClient::ObsClient(QObject *parent) : QObject(parent), m_previewWidth(kDefaultPreviewWidth)
{
    connect(&m_socket, &QWebSocket::textMessageReceived, this, &ObsClient::onTextMessageReceived);
    connect(&m_socket, &QWebSocket::errorOccurred, this, &ObsClient::onSocketError);
    connect(&m_socket, &QWebSocket::disconnected, this, &ObsClient::onSocketDisconnected);

    m_statusTimer.setInterval(kStatusPollIntervalMs);
    connect(&m_statusTimer, &QTimer::timeout, this, [this]() {
        if (m_state == Authenticated) {
            requestStreamStatus();
            requestRecordStatus();
            requestStats();
            // No event exists for a canvas resize, so poll for it.
            requestVideoSettings();
        }
    });

    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this,
            [this]() { connectToObs(m_host, m_port, m_password); });

    m_previewTimer.setInterval(kPreviewPollIntervalMs);
    connect(&m_previewTimer, &QTimer::timeout, this, [this]() {
        if (m_state != Authenticated || m_scenes.isEmpty())
            return;

        if (!m_currentProgramScene.isEmpty())
            requestSceneScreenshot(m_currentProgramScene);
        if (m_studioModeEnabled && !m_previewScene.isEmpty()
            && m_previewScene != m_currentProgramScene)
            requestSceneScreenshot(m_previewScene);

        ++m_previewTickCounter;
        if (m_previewTickCounter % kBackgroundRefreshEveryNTicks != 0)
            return;

        if (m_previewRoundRobinIndex >= m_scenes.size())
            m_previewRoundRobinIndex = 0;
        const QString sceneName = m_scenes.at(m_previewRoundRobinIndex)
                                          .toMap()
                                          .value(QStringLiteral("sceneName"))
                                          .toString();
        ++m_previewRoundRobinIndex;
        if (sceneName != m_currentProgramScene && sceneName != m_previewScene)
            requestSceneScreenshot(sceneName);
    });
}

void ObsClient::setState(State state)
{
    if (m_state == state)
        return;
    m_state = state;
    emit connectionStateChanged();
}

void ObsClient::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void ObsClient::connectToObs(const QString &host, int port, const QString &password)
{
    if (m_host != host || m_port != port) {
        m_host = host;
        m_port = port;
        emit connectionTargetChanged();
    }
    m_password = password;
    m_userRequestedDisconnect = false;

    setLastError(QString());
    setState(Connecting);

    QUrl url;
    url.setScheme(QStringLiteral("ws"));
    url.setHost(host);
    url.setPort(port);
    m_socket.open(url);
}

void ObsClient::disconnectFromObs()
{
    m_userRequestedDisconnect = true;
    m_reconnectTimer.stop();
    m_statusTimer.stop();
    m_previewTimer.stop();
    m_socket.close();
    setState(Disconnected);

    m_pendingRequests.clear();
    m_scenesAwaitingScreenshot.clear();

    m_scenes.clear();
    m_thumbnails.clear();
    m_sources.clear();
    m_sourceVisibility.clear();
    m_inputs.clear();
    m_inputMuted.clear();
    m_inputVolumes.clear();
    m_inputLevels.clear();
    m_currentProgramScene.clear();
    m_activeFps = 0.0;
    m_cpuUsage = 0.0;
    m_statsKnown = false;
    m_streamBitrateKbps = 0.0;
    m_streamSkippedFrames = 0;
    m_streamSkippedPercent = 0.0;
    m_lastStreamBytes = -1;
    m_lastStreamBytesMs = 0;
    m_lastLevelUpdateMs = 0;
    m_streaming = false;
    m_recording = false;
    m_streamTimecode = QStringLiteral("00:00:00");
    m_recordTimecode = QStringLiteral("00:00:00");
    m_recordDirectory.clear();
    m_videoAspect = 16.0 / 9.0;
    m_studioModeEnabled = false;
    m_previewScene.clear();
    m_transitions.clear();
    m_currentTransition.clear();
    m_previewRoundRobinIndex = 0;
    m_previewTickCounter = 0;
    emit scenesChanged();
    emit thumbnailsChanged();
    emit sourcesChanged();
    emit sourceVisibilityChanged();
    emit inputsChanged();
    emit inputMutedChanged();
    emit inputVolumesChanged();
    emit inputLevelsChanged();
    emit statsChanged();
    emit currentProgramSceneChanged();
    emit streamingChanged();
    emit recordingChanged();
    emit streamTimecodeChanged();
    emit recordTimecodeChanged();
    emit recordDirectoryChanged();
    emit videoAspectChanged();
    emit studioModeEnabledChanged();
    emit previewSceneChanged();
    emit transitionsChanged();
    emit currentTransitionChanged();
}

ObsClient::~ObsClient()
{
    // ~QWebSocket can emit disconnected() after the other members are gone.
    m_socket.disconnect(this);
}

void ObsClient::scheduleReconnect()
{
    if (m_userRequestedDisconnect)
        return;
    m_reconnectTimer.start(kReconnectDelayMs);
}

void ObsClient::onSocketError(QAbstractSocket::SocketError error)
{
    // Usually OBS isn't running or its WebSocket server is off (the default).
    if (error == QAbstractSocket::ConnectionRefusedError) {
        setLastError(tr("Connection refused. Is OBS running, with its WebSocket server "
                        "enabled under Tools → WebSocket Server Settings?"));
        return;
    }
    setLastError(m_socket.errorString());
}

void ObsClient::onSocketDisconnected()
{
    m_statusTimer.stop();
    m_previewTimer.stop();
    // The dropped callbacks would have cleared this set, so clear it here or
    // thumbnails never refresh after a reconnect.
    m_pendingRequests.clear();
    m_scenesAwaitingScreenshot.clear();

    // Retrying a wrong password can't succeed, so report it and stop.
    if (static_cast<int>(m_socket.closeCode()) == kCloseAuthenticationFailed) {
        setLastError(tr("OBS rejected the password."));
        setState(Disconnected);
        return;
    }

    setState(Disconnected);
    scheduleReconnect();
}

QString ObsClient::computeAuthResponse(const QString &password, const QString &salt,
                                       const QString &challenge)
{
    const QByteArray secretHash =
            QCryptographicHash::hash((password + salt).toUtf8(), QCryptographicHash::Sha256)
                    .toBase64();
    const QByteArray authHash =
            QCryptographicHash::hash(secretHash + challenge.toUtf8(), QCryptographicHash::Sha256)
                    .toBase64();
    return QString::fromUtf8(authHash);
}

void ObsClient::onTextMessageReceived(const QString &message)
{
    const QJsonObject root = QJsonDocument::fromJson(message.toUtf8()).object();
    const int op = root.value(QStringLiteral("op")).toInt(-1);
    const QJsonObject d = root.value(QStringLiteral("d")).toObject();

    switch (op) {
    case kOpHello:
        handleHello(d);
        break;
    case kOpIdentified:
        handleIdentified(d);
        break;
    case kOpEvent:
        handleEvent(d);
        break;
    case kOpRequestResponse:
        handleRequestResponse(d);
        break;
    default:
        qWarning() << "ObsClient: unhandled opcode" << op;
        break;
    }
}

void ObsClient::handleHello(const QJsonObject &d)
{
    QJsonObject identifyData;
    identifyData[QStringLiteral("rpcVersion")] = kRpcVersion;
    identifyData[QStringLiteral("eventSubscriptions")] =
            kEventSubscriptionAll | kEventSubscriptionInputVolumeMeters;

    if (d.contains(QStringLiteral("authentication"))) {
        const QJsonObject auth = d.value(QStringLiteral("authentication")).toObject();
        const QString challenge = auth.value(QStringLiteral("challenge")).toString();
        const QString salt = auth.value(QStringLiteral("salt")).toString();
        identifyData[QStringLiteral("authentication")] =
                computeAuthResponse(m_password, salt, challenge);
    }

    QJsonObject envelope;
    envelope[QStringLiteral("op")] = kOpIdentify;
    envelope[QStringLiteral("d")] = identifyData;
    m_socket.sendTextMessage(
            QString::fromUtf8(QJsonDocument(envelope).toJson(QJsonDocument::Compact)));
}

void ObsClient::handleIdentified(const QJsonObject &)
{
    setState(Authenticated);
    setLastError(QString());

    requestVideoSettings();
    requestSceneList();
    requestInputList();
    requestStreamStatus();
    requestRecordStatus();
    requestRecordDirectory();
    requestStats();
    requestStudioModeState();
    requestTransitionList();
    m_statusTimer.start();
    m_previewTimer.start();
}

void ObsClient::sendRequest(const QString &requestType, const QJsonObject &requestData,
                            ResponseCallback callback)
{
    if (m_state != Authenticated && m_state != Connected) {
        qWarning() << "ObsClient: dropping request, not connected:" << requestType;
        return;
    }

    const QString requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    QJsonObject inner;
    inner[QStringLiteral("requestType")] = requestType;
    inner[QStringLiteral("requestId")] = requestId;
    if (!requestData.isEmpty())
        inner[QStringLiteral("requestData")] = requestData;

    QJsonObject envelope;
    envelope[QStringLiteral("op")] = kOpRequest;
    envelope[QStringLiteral("d")] = inner;

    if (callback)
        m_pendingRequests.insert(requestId, std::move(callback));

    m_socket.sendTextMessage(
            QString::fromUtf8(QJsonDocument(envelope).toJson(QJsonDocument::Compact)));
}

void ObsClient::handleRequestResponse(const QJsonObject &d)
{
    const QString requestId = d.value(QStringLiteral("requestId")).toString();
    auto it = m_pendingRequests.find(requestId);
    if (it == m_pendingRequests.end())
        return;

    ResponseCallback callback = it.value();
    m_pendingRequests.erase(it);

    const QJsonObject status = d.value(QStringLiteral("requestStatus")).toObject();
    const bool ok = status.value(QStringLiteral("result")).toBool();
    const QString comment = status.value(QStringLiteral("comment")).toString();
    const QJsonObject responseData = d.value(QStringLiteral("responseData")).toObject();

    if (!ok)
        qWarning() << "ObsClient: request failed:" << comment;

    if (callback)
        callback(ok, responseData, comment);
}

void ObsClient::handleEvent(const QJsonObject &d)
{
    const QString eventType = d.value(QStringLiteral("eventType")).toString();
    const QJsonObject data = d.value(QStringLiteral("eventData")).toObject();

    if (eventType == QStringLiteral("CurrentProgramSceneChanged")) {
        m_currentProgramScene = data.value(QStringLiteral("sceneName")).toString();
        emit currentProgramSceneChanged();
        requestSceneItemList(m_currentProgramScene);
        requestSceneScreenshot(m_currentProgramScene);
    } else if (eventType == QStringLiteral("SceneListChanged")
               || eventType == QStringLiteral("SceneNameChanged")) {
        requestSceneList();
    } else if (eventType == QStringLiteral("SceneItemEnableStateChanged")) {
        const int sceneItemId = data.value(QStringLiteral("sceneItemId")).toInt();
        const bool enabled = data.value(QStringLiteral("sceneItemEnabled")).toBool();
        m_sourceVisibility[QString::number(sceneItemId)] = enabled;
        emit sourceVisibilityChanged();
    } else if (eventType == QStringLiteral("InputMuteStateChanged")) {
        const QString inputName = data.value(QStringLiteral("inputName")).toString();
        m_inputMuted[inputName] = data.value(QStringLiteral("inputMuted")).toBool();
        emit inputMutedChanged();
    } else if (eventType == QStringLiteral("InputVolumeMeters")) {
        applyInputLevels(data.value(QStringLiteral("inputs")).toArray());
    } else if (eventType == QStringLiteral("InputVolumeChanged")) {
        const QString inputName = data.value(QStringLiteral("inputName")).toString();
        m_inputVolumes[inputName] = data.value(QStringLiteral("inputVolumeDb")).toDouble();
        emit inputVolumesChanged();
    } else if (eventType == QStringLiteral("InputCreated")
               || eventType == QStringLiteral("InputRemoved")
               || eventType == QStringLiteral("InputNameChanged")) {
        requestInputList();
    } else if (eventType == QStringLiteral("StreamStateChanged")) {
        m_streaming = data.value(QStringLiteral("outputActive")).toBool();
        emit streamingChanged();
    } else if (eventType == QStringLiteral("RecordStateChanged")) {
        m_recording = data.value(QStringLiteral("outputActive")).toBool();
        emit recordingChanged();
        requestRecordDirectory();
    } else if (eventType == QStringLiteral("StudioModeStateChanged")) {
        m_studioModeEnabled = data.value(QStringLiteral("studioModeEnabled")).toBool();
        emit studioModeEnabledChanged();
        if (m_studioModeEnabled) {
            requestCurrentPreviewScene();
        } else {
            m_previewScene.clear();
            emit previewSceneChanged();
        }
    } else if (eventType == QStringLiteral("CurrentPreviewSceneChanged")) {
        m_previewScene = data.value(QStringLiteral("sceneName")).toString();
        emit previewSceneChanged();
    } else if (eventType == QStringLiteral("CurrentSceneTransitionChanged")) {
        m_currentTransition = data.value(QStringLiteral("transitionName")).toString();
        emit currentTransitionChanged();
    }
}

void ObsClient::requestSceneList()
{
    sendRequest(QStringLiteral("GetSceneList"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;

                    m_currentProgramScene =
                            data.value(QStringLiteral("currentProgramSceneName")).toString();
                    emit currentProgramSceneChanged();

                    QVariantList scenes;
                    const QJsonArray array = data.value(QStringLiteral("scenes")).toArray();
                    for (const auto &value : array) {
                        const QJsonObject scene = value.toObject();
                        QVariantMap map;
                        map[QStringLiteral("sceneName")] =
                                scene.value(QStringLiteral("sceneName")).toString();
                        map[QStringLiteral("sceneIndex")] =
                                scene.value(QStringLiteral("sceneIndex")).toInt();
                        scenes.append(map);
                    }
                    m_scenes = scenes;
                    emit scenesChanged();

                    for (const auto &variant : std::as_const(m_scenes))
                        requestSceneScreenshot(
                                variant.toMap().value(QStringLiteral("sceneName")).toString());

                    if (!m_currentProgramScene.isEmpty())
                        requestSceneItemList(m_currentProgramScene);
                });
}

void ObsClient::requestSceneItemList(const QString &sceneName)
{
    QJsonObject requestData;
    requestData[QStringLiteral("sceneName")] = sceneName;

    sendRequest(QStringLiteral("GetSceneItemList"), requestData,
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;

                    QVariantList sources;
                    QVariantMap visibility;
                    const QJsonArray array = data.value(QStringLiteral("sceneItems")).toArray();
                    for (const auto &value : array) {
                        const QJsonObject item = value.toObject();
                        const int sceneItemId = item.value(QStringLiteral("sceneItemId")).toInt();
                        QVariantMap map;
                        map[QStringLiteral("sourceName")] =
                                item.value(QStringLiteral("sourceName")).toString();
                        map[QStringLiteral("sceneItemId")] = sceneItemId;
                        map[QStringLiteral("inputKind")] =
                                item.value(QStringLiteral("inputKind")).toString();
                        sources.append(map);
                        visibility[QString::number(sceneItemId)] =
                                item.value(QStringLiteral("sceneItemEnabled")).toBool();
                    }
                    m_sources = sources;
                    emit sourcesChanged();
                    m_sourceVisibility = visibility;
                    emit sourceVisibilityChanged();
                });
}

void ObsClient::requestVideoSettings()
{
    sendRequest(QStringLiteral("GetVideoSettings"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;

                    const double width = data.value(QStringLiteral("baseWidth")).toDouble();
                    const double height = data.value(QStringLiteral("baseHeight")).toDouble();
                    if (width <= 0 || height <= 0)
                        return;

                    const qreal aspect = width / height;
                    if (qFuzzyCompare(aspect, m_videoAspect))
                        return;

                    m_videoAspect = aspect;
                    emit videoAspectChanged();

                    // Existing thumbnails have the old aspect; refetch them all.
                    for (const auto &variant : std::as_const(m_scenes))
                        requestSceneScreenshot(
                                variant.toMap().value(QStringLiteral("sceneName")).toString());
                });
}

void ObsClient::setPreviewWidth(int width)
{
    // Rounded up to a step, so the image is at least as wide as its box.
    const int snapped = qBound(kMinPreviewWidth,
                               int(std::ceil(qreal(width) / kPreviewWidthStep)) * kPreviewWidthStep,
                               kMaxPreviewWidth);
    if (snapped == m_previewWidth)
        return;

    m_previewWidth = snapped;
    emit previewWidthChanged();

    // No refetch: this changes continuously during a resize, and polling soon
    // replaces the thumbnails that matter.
}

void ObsClient::requestSceneScreenshot(const QString &sceneName)
{
    if (sceneName.isEmpty())
        return;

    // One request in flight per scene, so a slow link or busy OBS skips ticks
    // instead of building a backlog.
    if (m_scenesAwaitingScreenshot.contains(sceneName))
        return;
    m_scenesAwaitingScreenshot.insert(sceneName);

    QJsonObject requestData;
    requestData[QStringLiteral("sourceName")] = sceneName;
    requestData[QStringLiteral("imageFormat")] = QStringLiteral("jpg");
    // OBS scales to exactly this size, so match the canvas aspect, which can
    // change independently of the width.
    int width = m_previewWidth;
    int height = qMax(1, qRound(width / m_videoAspect));
    if (height > kMaxPreviewHeight) {
        height = kMaxPreviewHeight;
        width = qMax(1, qRound(height * m_videoAspect));
    }
    requestData[QStringLiteral("imageWidth")] = width;
    requestData[QStringLiteral("imageHeight")] = height;
    requestData[QStringLiteral("imageCompressionQuality")] = kPreviewCompressionQuality;

    sendRequest(QStringLiteral("GetSourceScreenshot"), requestData,
                [this, sceneName](bool ok, const QJsonObject &data, const QString &) {
                    m_scenesAwaitingScreenshot.remove(sceneName);
                    if (!ok)
                        return;
                    updateSceneThumbnail(sceneName,
                                         data.value(QStringLiteral("imageData")).toString());
                });
}

void ObsClient::updateSceneThumbnail(const QString &sceneName, const QString &imageData)
{
    if (imageData.isEmpty())
        return;

    const QString dataUrl = imageData.startsWith(QStringLiteral("data:"))
            ? imageData
            : QStringLiteral("data:image/jpg;base64,") + imageData;

    if (m_thumbnails.value(sceneName).toString() == dataUrl)
        return;

    m_thumbnails[sceneName] = dataUrl;
    emit thumbnailsChanged();
}

void ObsClient::requestInputList()
{
    sendRequest(QStringLiteral("GetInputList"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;

                    QVariantList inputs;
                    const QJsonArray array = data.value(QStringLiteral("inputs")).toArray();
                    for (const auto &value : array) {
                        const QJsonObject input = value.toObject();
                        const QString kind = input.value(QStringLiteral("inputKind")).toString();
                        if (!isLikelyAudioInputKind(kind))
                            continue;

                        QVariantMap map;
                        map[QStringLiteral("inputName")] =
                                input.value(QStringLiteral("inputName")).toString();
                        map[QStringLiteral("inputKind")] = kind;
                        inputs.append(map);
                    }
                    m_inputs = inputs;
                    emit inputsChanged();

                    for (const auto &variant : std::as_const(m_inputs))
                        requestInputState(
                                variant.toMap().value(QStringLiteral("inputName")).toString());
                });
}

void ObsClient::requestInputState(const QString &inputName)
{
    QJsonObject requestData;
    requestData[QStringLiteral("inputName")] = inputName;

    sendRequest(QStringLiteral("GetInputMute"), requestData,
                [this, inputName](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    m_inputMuted[inputName] = data.value(QStringLiteral("inputMuted")).toBool();
                    emit inputMutedChanged();
                });

    sendRequest(QStringLiteral("GetInputVolume"), requestData,
                [this, inputName](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    m_inputVolumes[inputName] =
                            data.value(QStringLiteral("inputVolumeDb")).toDouble();
                    emit inputVolumesChanged();
                });
}

void ObsClient::applyInputLevels(const QJsonArray &inputs)
{
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const qreal elapsedSec = m_lastLevelUpdateMs > 0 ? (nowMs - m_lastLevelUpdateMs) / 1000.0 : 0.0;
    m_lastLevelUpdateMs = nowMs;
    // The fall for this update, as a fraction of the meter scale.
    const qreal decay = elapsedSec * kMeterPeakDecayDbPerSecond / -kMeterFloorDb;
    // Clamped (unlike OBS) because a late update would otherwise overshoot.
    const qreal magnitudeAttack = qMin(1.0, elapsedSec / kMagnitudeIntegrationSec * 0.99);

    bool changed = false;

    for (const auto &value : inputs) {
        const QJsonObject input = value.toObject();
        const QString inputName = input.value(QStringLiteral("inputName")).toString();
        if (inputName.isEmpty())
            continue;

        // Muted or idle inputs send no channels; keep the last count so their
        // bars fall to silence instead of disappearing.
        const QJsonArray channels = input.value(QStringLiteral("inputLevelsMul")).toArray();
        const QVariantList previousChannels = m_inputLevels.value(inputName).toList();
        const int channelCount = channels.isEmpty() ? previousChannels.size() : channels.size();

        QVariantList levels;
        levels.reserve(channelCount);
        bool inputChanged = channelCount != previousChannels.size();

        for (int i = 0; i < channelCount; ++i) {
            const QVariantMap previous =
                    i < previousChannels.size() ? previousChannels.at(i).toMap() : QVariantMap();
            const qreal previousPeak = previous.value(QStringLiteral("peak")).toDouble();
            const qreal previousMagnitude = previous.value(QStringLiteral("magnitude")).toDouble();

            qreal peakTarget = 0.0;
            qreal magnitudeTarget = 0.0;
            if (i < channels.size()) {
                const QJsonArray channel = channels.at(i).toArray();
                peakTarget = levelFractionFromMultiplier(channel.at(kMeterPeakIndex).toDouble());
                magnitudeTarget =
                        levelFractionFromMultiplier(channel.at(kMeterMagnitudeIndex).toDouble());
            }

            // Rise immediately, fall at the decay rate.
            const qreal peak = qMax(peakTarget, previousPeak - decay);
            // Magnitude is smoothed both ways, except on a channel's first update.
            const qreal magnitude = previous.isEmpty()
                    ? magnitudeTarget
                    : previousMagnitude + (magnitudeTarget - previousMagnitude) * magnitudeAttack;

            if (qAbs(peak - previousPeak) >= kMeterEpsilon
                || qAbs(magnitude - previousMagnitude) >= kMeterEpsilon)
                inputChanged = true;

            levels.append(QVariantMap{
                    { QStringLiteral("peak"), peak },
                    { QStringLiteral("magnitude"), magnitude },
            });
        }

        if (!inputChanged)
            continue;

        m_inputLevels[inputName] = levels;
        changed = true;
    }

    // Only notify on visible changes, so silence costs no repaints.
    if (changed)
        emit inputLevelsChanged();
}

void ObsClient::requestStreamStatus()
{
    sendRequest(QStringLiteral("GetStreamStatus"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    m_streaming = data.value(QStringLiteral("outputActive")).toBool();
                    emit streamingChanged();
                    m_streamTimecode = data.value(QStringLiteral("outputTimecode"))
                                               .toString(QStringLiteral("00:00:00"));
                    emit streamTimecodeChanged();

                    m_streamSkippedFrames =
                            data.value(QStringLiteral("outputSkippedFrames")).toInt();
                    const int totalFrames = data.value(QStringLiteral("outputTotalFrames")).toInt();
                    m_streamSkippedPercent =
                            totalFrames > 0 ? 100.0 * m_streamSkippedFrames / totalFrames : 0.0;

                    // Rate from the byte counter; bits per ms equals kbit/s.
                    const qint64 bytes = static_cast<qint64>(
                            data.value(QStringLiteral("outputBytes")).toDouble());
                    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
                    if (!m_streaming) {
                        m_streamBitrateKbps = 0.0;
                        m_lastStreamBytes = -1;
                    } else if (m_lastStreamBytes >= 0 && nowMs > m_lastStreamBytesMs) {
                        const qint64 deltaBytes = qMax<qint64>(0, bytes - m_lastStreamBytes);
                        m_streamBitrateKbps = (deltaBytes * 8.0) / (nowMs - m_lastStreamBytesMs);
                    }
                    if (m_streaming) {
                        m_lastStreamBytes = bytes;
                        m_lastStreamBytesMs = nowMs;
                    }

                    emit statsChanged();
                });
}

void ObsClient::requestStats()
{
    sendRequest(QStringLiteral("GetStats"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    // Missing fields would read as zero; treat them as unknown.
                    if (!data.contains(QStringLiteral("activeFps")))
                        return;
                    m_activeFps = data.value(QStringLiteral("activeFps")).toDouble();
                    m_cpuUsage = data.value(QStringLiteral("cpuUsage")).toDouble();
                    // The status bar hides FPS and CPU until this is set.
                    m_statsKnown = true;
                    emit statsChanged();
                });
}

void ObsClient::requestRecordStatus()
{
    sendRequest(QStringLiteral("GetRecordStatus"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    m_recording = data.value(QStringLiteral("outputActive")).toBool();
                    emit recordingChanged();
                    m_recordTimecode = data.value(QStringLiteral("outputTimecode"))
                                               .toString(QStringLiteral("00:00:00"));
                    emit recordTimecodeChanged();
                });
}

// Fetched on connect and when recording starts or stops; there's no event for it.
void ObsClient::requestRecordDirectory()
{
    sendRequest(QStringLiteral("GetRecordDirectory"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    const QString directory =
                            data.value(QStringLiteral("recordDirectory")).toString();
                    if (directory == m_recordDirectory)
                        return;
                    m_recordDirectory = directory;
                    emit recordDirectoryChanged();
                });
}

void ObsClient::requestStudioModeState()
{
    sendRequest(QStringLiteral("GetStudioModeEnabled"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    m_studioModeEnabled = data.value(QStringLiteral("studioModeEnabled")).toBool();
                    emit studioModeEnabledChanged();
                    if (m_studioModeEnabled)
                        requestCurrentPreviewScene();
                });
}

void ObsClient::requestCurrentPreviewScene()
{
    sendRequest(QStringLiteral("GetCurrentPreviewScene"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;
                    // `sceneName` since obs-websocket 5.3; `currentPreviewSceneName`
                    // before that, and deprecated.
                    m_previewScene =
                            data.value(QStringLiteral("sceneName"))
                                    .toString(data.value(QStringLiteral("currentPreviewSceneName"))
                                                      .toString());
                    emit previewSceneChanged();
                });
}

void ObsClient::requestTransitionList()
{
    sendRequest(QStringLiteral("GetSceneTransitionList"), { },
                [this](bool ok, const QJsonObject &data, const QString &) {
                    if (!ok)
                        return;

                    QVariantList transitions;
                    const QJsonArray array = data.value(QStringLiteral("transitions")).toArray();
                    for (const auto &value : array) {
                        const QString name =
                                value.toObject().value(QStringLiteral("transitionName")).toString();
                        if (!name.isEmpty())
                            transitions.append(name);
                    }
                    m_transitions = transitions;
                    emit transitionsChanged();

                    m_currentTransition =
                            data.value(QStringLiteral("currentSceneTransitionName")).toString();
                    emit currentTransitionChanged();
                });
}

void ObsClient::setCurrentProgramScene(const QString &sceneName)
{
    QJsonObject requestData;
    requestData[QStringLiteral("sceneName")] = sceneName;
    sendRequest(QStringLiteral("SetCurrentProgramScene"), requestData);
}

void ObsClient::setSceneItemEnabled(const QString &sceneName, int sceneItemId, bool enabled)
{
    QJsonObject requestData;
    requestData[QStringLiteral("sceneName")] = sceneName;
    requestData[QStringLiteral("sceneItemId")] = sceneItemId;
    requestData[QStringLiteral("sceneItemEnabled")] = enabled;
    sendRequest(QStringLiteral("SetSceneItemEnabled"), requestData);
}

void ObsClient::toggleInputMute(const QString &inputName)
{
    QJsonObject requestData;
    requestData[QStringLiteral("inputName")] = inputName;
    sendRequest(QStringLiteral("ToggleInputMute"), requestData);
}

void ObsClient::setInputVolumeDb(const QString &inputName, float volumeDb)
{
    QJsonObject requestData;
    requestData[QStringLiteral("inputName")] = inputName;
    requestData[QStringLiteral("inputVolumeDb")] = volumeDb;
    sendRequest(QStringLiteral("SetInputVolume"), requestData);
}

void ObsClient::startStream()
{
    sendRequest(QStringLiteral("StartStream"));
}
void ObsClient::stopStream()
{
    sendRequest(QStringLiteral("StopStream"));
}
void ObsClient::toggleStream()
{
    sendRequest(QStringLiteral("ToggleStream"));
}

void ObsClient::startRecord()
{
    sendRequest(QStringLiteral("StartRecord"));
}
void ObsClient::stopRecord()
{
    sendRequest(QStringLiteral("StopRecord"));
}
void ObsClient::toggleRecord()
{
    sendRequest(QStringLiteral("ToggleRecord"));
}

void ObsClient::setStudioModeEnabled(bool enabled)
{
    QJsonObject requestData;
    requestData[QStringLiteral("studioModeEnabled")] = enabled;
    sendRequest(QStringLiteral("SetStudioModeEnabled"), requestData);
}

void ObsClient::setCurrentPreviewScene(const QString &sceneName)
{
    QJsonObject requestData;
    requestData[QStringLiteral("sceneName")] = sceneName;
    sendRequest(QStringLiteral("SetCurrentPreviewScene"), requestData);
}

void ObsClient::triggerStudioModeTransition()
{
    sendRequest(QStringLiteral("TriggerStudioModeTransition"));
}

void ObsClient::setCurrentTransition(const QString &transitionName)
{
    QJsonObject requestData;
    requestData[QStringLiteral("transitionName")] = transitionName;
    sendRequest(QStringLiteral("SetCurrentSceneTransition"), requestData);
}
