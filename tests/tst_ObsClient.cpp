// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#include <QtTest/QtTest>
#include <QCryptographicHash>
#include <QJsonArray>
#include <QSet>

#include "MockObsServer.h"
#include "ObsClient.h"
#include "ConnectionProbe.h"

namespace {

// Independent of ObsClient::computeAuthResponse, as a second implementation of
// the documented auth algorithm.
QString referenceAuthResponse(const QString &password, const QString &salt,
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

// Completes the handshake as soon as a client connects.
void autoIdentify(MockObsServer &server)
{
    QObject::connect(&server, &MockObsServer::clientConnected, &server,
                     [&server]() { server.sendHello(); });
    QObject::connect(&server, &MockObsServer::identifyReceived, &server,
                     [&server](const QJsonObject &) { server.sendIdentified(); });
}

QJsonObject makeScene(const QString &name, int index)
{
    QJsonObject scene;
    scene[QStringLiteral("sceneName")] = name;
    scene[QStringLiteral("sceneIndex")] = index;
    return scene;
}

QJsonObject makeInput(const QString &name, const QString &kind)
{
    QJsonObject input;
    input[QStringLiteral("inputName")] = name;
    input[QStringLiteral("inputKind")] = kind;
    return input;
}

} // namespace

class TestObsClient : public QObject
{
    Q_OBJECT

private slots:
    void authResponseMatchesDocumentedAlgorithm();
    void connectsWithoutAuthentication();
    void connectsWithCorrectPassword();
    void rejectsIncorrectPassword();
    void parsesSceneListAndSwitchesScene();
    void appliesMuteStateChangedEvent();
    void appliesVolumeChangedEvent();

    void parsesSceneItemListAndTogglesVisibility();
    void appliesCurrentProgramSceneChangedEvent();
    void parsesSceneScreenshotsIntoThumbnails();
    void sceneListChangedPreservesThumbnailDuringRefresh();
    void requestsThumbnailsAtTheWidthTheUiAsksFor();
    void clampsThumbnailSizeAtBothExtremes();
    void clampsThumbnailHeightOnATallCanvas();
    void skipsThumbnailRequestWhileTheLastIsStillInFlight();

    void filtersNonAudioInputsFromInputList();
    void populatesInitialInputMuteAndVolumeFromGetRequests();
    void inputCreatedEventTriggersInputListRefresh();
    void audioControlRequestsUseCorrectTypes();

    void streamAndRecordStatusParsed();
    void recordDirectoryFollowsObs();
    void streamAndRecordControlRequestsUseCorrectTypes();

    void exposesConnectionTarget();
    void probeReportsWhatIsListening();
    void refusedConnectionSaysWhereToLook();
    void subscribesToVolumeMeterEvents();
    void appliesInputVolumeMetersEvent();
    void keepsALevelPerAudioChannel();
    void magnitudeIsIntegratedWhereThePeakIsNot();
    void inputLevelRisesImmediatelyAndFallsGradually();
    void parsesStatsIntoPerformanceProperties();
    void statsAreUnknownUntilObsAnswers();
    void derivesStreamBitrateFromByteCounter();

    void disconnectResetsState();
    void reconnectsAfterUnexpectedDisconnect();
    void failedAttemptIsNotRetried();
    void droppedConnectionRetriesWithASteadyMessage();
    void malformedMessageDoesNotCrash();

    void populatesStudioModeStateOnConnect();
    void enteringStudioModeFetchesPreviewScene();
    void previewSceneTakesEitherOfTheNamesObsHasUsed();
    void appliesCurrentPreviewSceneChangedEvent();
    void parsesTransitionList();
    void appliesCurrentSceneTransitionChangedEvent();
    void studioModeControlRequestsUseCorrectTypes();
};

void TestObsClient::authResponseMatchesDocumentedAlgorithm()
{
    const QString password = QStringLiteral("supersecretpassword");
    const QString salt = QStringLiteral("PZVbYpvXKZD8afeH4gTUuXfPCK9nCV5A9Bh8WGvhWmw=");
    const QString challenge = QStringLiteral("d+ez3Fjb0OFysDoBoNhTanASJz8DTv9zN7HmnPzsQz8=");

    const QString expected = referenceAuthResponse(password, salt, challenge);
    QCOMPARE(ObsClient::computeAuthResponse(password, salt, challenge), expected);

    // Different passwords must not collide.
    QVERIFY(ObsClient::computeAuthResponse(QStringLiteral("other"), salt, challenge) != expected);
}

void TestObsClient::connectsWithoutAuthentication()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
}

void TestObsClient::connectsWithCorrectPassword()
{
    MockObsServer server;
    QVERIFY(server.start());

    const QString password = QStringLiteral("hunter2");
    const QString salt = QStringLiteral("c2FsdHNhbHRzYWx0c2FsdHNhbHRzYWx0");
    const QString challenge = QStringLiteral("Y2hhbGxlbmdlY2hhbGxlbmdlY2hhbGxlbmdl");
    const QString expectedAuth = referenceAuthResponse(password, salt, challenge);

    connect(&server, &MockObsServer::clientConnected, &server, [&]() {
        QJsonObject auth;
        auth[QStringLiteral("challenge")] = challenge;
        auth[QStringLiteral("salt")] = salt;
        server.sendHello(auth);
    });
    connect(&server, &MockObsServer::identifyReceived, &server, [&](const QJsonObject &d) {
        if (d.value(QStringLiteral("authentication")).toString() == expectedAuth)
            server.sendIdentified();
    });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), password);

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
}

void TestObsClient::rejectsIncorrectPassword()
{
    MockObsServer server;
    QVERIFY(server.start());

    const QString salt = QStringLiteral("c2FsdHNhbHRzYWx0c2FsdHNhbHRzYWx0");
    const QString challenge = QStringLiteral("Y2hhbGxlbmdlY2hhbGxlbmdlY2hhbGxlbmdl");
    const QString expectedAuth =
            referenceAuthResponse(QStringLiteral("correct-password"), salt, challenge);

    connect(&server, &MockObsServer::clientConnected, &server, [&]() {
        QJsonObject auth;
        auth[QStringLiteral("challenge")] = challenge;
        auth[QStringLiteral("salt")] = salt;
        server.sendHello(auth);
    });
    connect(&server, &MockObsServer::identifyReceived, &server, [&](const QJsonObject &d) {
        if (d.value(QStringLiteral("authentication")).toString() == expectedAuth)
            server.sendIdentified();
        else if (server.clientSocket())
            // As OBS does: close with AuthenticationFailed.
            server.clientSocket()->close(static_cast<QWebSocketProtocol::CloseCode>(4009),
                                         QStringLiteral("Authentication failed."));
    });
    int connections = 0;
    connect(&server, &MockObsServer::clientConnected, &server, [&]() { ++connections; });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(),
                        QStringLiteral("wrong-password"));

    QTRY_VERIFY(client.lastError().contains(QStringLiteral("password")));
    QCOMPARE(client.connectionState(), ObsClient::Disconnected);

    // No retry: wait past the 3 s reconnect delay.
    QTest::qWait(3500);
    QCOMPARE(connections, 1);
    QCOMPARE(client.connectionState(), ObsClient::Disconnected);
}

void TestObsClient::parsesSceneListAndSwitchesScene()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    QString switchedTo;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &data) {
                if (type == QStringLiteral("GetSceneList")) {
                    QJsonArray scenes;
                    scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                    scenes.append(makeScene(QStringLiteral("Scene B"), 1));

                    QJsonObject responseData;
                    responseData[QStringLiteral("currentProgramSceneName")] =
                            QStringLiteral("Scene A");
                    responseData[QStringLiteral("scenes")] = scenes;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("SetCurrentProgramScene")) {
                    switchedTo = data.value(QStringLiteral("sceneName")).toString();
                    server.sendRequestResponse(requestId, true);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.scenes().size(), 2);
    QCOMPARE(client.currentProgramScene(), QStringLiteral("Scene A"));

    client.setCurrentProgramScene(QStringLiteral("Scene B"));
    QTRY_COMPARE(switchedTo, QStringLiteral("Scene B"));
}

void TestObsClient::appliesMuteStateChangedEvent()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetInputList")) {
                    QJsonArray inputs;
                    inputs.append(makeInput(QStringLiteral("Mic"),
                                            QStringLiteral("pulse_input_capture")));
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputs")] = inputs;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.inputs().size(), 1);
    // The initial GetInputMute answer must not undo the event.
    QTRY_COMPARE(server.answeredCount(QStringLiteral("GetInputMute")), 1);

    QJsonObject eventData;
    eventData[QStringLiteral("inputName")] = QStringLiteral("Mic");
    eventData[QStringLiteral("inputMuted")] = true;
    server.sendEvent(QStringLiteral("InputMuteStateChanged"), eventData);

    QTRY_VERIFY(client.inputMuted().value(QStringLiteral("Mic")).toBool());
}

void TestObsClient::appliesVolumeChangedEvent()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetInputList")) {
                    QJsonArray inputs;
                    inputs.append(makeInput(QStringLiteral("Desktop Audio"),
                                            QStringLiteral("wasapi_output_capture")));
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputs")] = inputs;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.inputs().size(), 1);
    // The initial GetInputVolume answer must not undo the event.
    QTRY_COMPARE(server.answeredCount(QStringLiteral("GetInputVolume")), 1);

    QJsonObject eventData;
    eventData[QStringLiteral("inputName")] = QStringLiteral("Desktop Audio");
    eventData[QStringLiteral("inputVolumeDb")] = -12.5;
    server.sendEvent(QStringLiteral("InputVolumeChanged"), eventData);

    QTRY_COMPARE(client.inputVolumes().value(QStringLiteral("Desktop Audio")).toDouble(), -12.5);
}

void TestObsClient::parsesSceneItemListAndTogglesVisibility()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    QJsonObject lastSetSceneItemEnabledRequest;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &data) {
                if (type == QStringLiteral("GetSceneList")) {
                    QJsonArray scenes;
                    scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                    QJsonObject responseData;
                    responseData[QStringLiteral("currentProgramSceneName")] =
                            QStringLiteral("Scene A");
                    responseData[QStringLiteral("scenes")] = scenes;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetSceneItemList")) {
                    QJsonObject item;
                    item[QStringLiteral("sourceName")] = QStringLiteral("Camera");
                    item[QStringLiteral("sceneItemId")] = 1;
                    item[QStringLiteral("sceneItemEnabled")] = true;
                    item[QStringLiteral("inputKind")] = QStringLiteral("v4l2_input");

                    QJsonArray items;
                    items.append(item);
                    QJsonObject responseData;
                    responseData[QStringLiteral("sceneItems")] = items;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("SetSceneItemEnabled")) {
                    lastSetSceneItemEnabledRequest = data;
                    server.sendRequestResponse(requestId, true);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.sources().size(), 1);

    const QVariantMap source = client.sources().first().toMap();
    QCOMPARE(source.value(QStringLiteral("sourceName")).toString(), QStringLiteral("Camera"));
    QCOMPARE(source.value(QStringLiteral("sceneItemId")).toInt(), 1);
    QVERIFY(client.sourceVisibility().value(QStringLiteral("1")).toBool());

    client.setSceneItemEnabled(QStringLiteral("Scene A"), 1, false);
    QTRY_COMPARE(lastSetSceneItemEnabledRequest.value(QStringLiteral("sceneName")).toString(),
                 QStringLiteral("Scene A"));
    QCOMPARE(lastSetSceneItemEnabledRequest.value(QStringLiteral("sceneItemId")).toInt(), 1);
    QCOMPARE(lastSetSceneItemEnabledRequest.value(QStringLiteral("sceneItemEnabled")).toBool(),
             false);

    QJsonObject eventData;
    eventData[QStringLiteral("sceneName")] = QStringLiteral("Scene A");
    eventData[QStringLiteral("sceneItemId")] = 1;
    eventData[QStringLiteral("sceneItemEnabled")] = false;
    server.sendEvent(QStringLiteral("SceneItemEnableStateChanged"), eventData);

    QTRY_VERIFY(!client.sourceVisibility().value(QStringLiteral("1")).toBool());
}

void TestObsClient::appliesCurrentProgramSceneChangedEvent()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    bool sawSceneItemListForB = false;
    bool sawScreenshotForB = false;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &data) {
                if (type == QStringLiteral("GetSceneList")) {
                    QJsonArray scenes;
                    scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                    scenes.append(makeScene(QStringLiteral("Scene B"), 1));
                    QJsonObject responseData;
                    responseData[QStringLiteral("currentProgramSceneName")] =
                            QStringLiteral("Scene A");
                    responseData[QStringLiteral("scenes")] = scenes;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetSceneItemList")) {
                    if (data.value(QStringLiteral("sceneName")).toString()
                        == QStringLiteral("Scene B"))
                        sawSceneItemListForB = true;
                    server.sendRequestResponse(requestId, true, { });
                } else if (type == QStringLiteral("GetSourceScreenshot")) {
                    if (data.value(QStringLiteral("sourceName")).toString()
                        == QStringLiteral("Scene B"))
                        sawScreenshotForB = true;
                    server.sendRequestResponse(requestId, true, { });
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.scenes().size(), 2);

    QJsonObject eventData;
    eventData[QStringLiteral("sceneName")] = QStringLiteral("Scene B");
    server.sendEvent(QStringLiteral("CurrentProgramSceneChanged"), eventData);

    QTRY_COMPARE(client.currentProgramScene(), QStringLiteral("Scene B"));
    QTRY_VERIFY(sawSceneItemListForB);
    QTRY_VERIFY(sawScreenshotForB);
}

void TestObsClient::parsesSceneScreenshotsIntoThumbnails()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &data) {
                if (type == QStringLiteral("GetSceneList")) {
                    QJsonArray scenes;
                    scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                    scenes.append(makeScene(QStringLiteral("Scene B"), 1));
                    QJsonObject responseData;
                    responseData[QStringLiteral("currentProgramSceneName")] =
                            QStringLiteral("Scene A");
                    responseData[QStringLiteral("scenes")] = scenes;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetSourceScreenshot")) {
                    const QString sourceName = data.value(QStringLiteral("sourceName")).toString();
                    QJsonObject responseData;
                    if (sourceName == QStringLiteral("Scene A"))
                        responseData[QStringLiteral("imageData")] =
                                QStringLiteral("data:image/jpeg;base64,QUFB"); // already prefixed
                    else if (sourceName == QStringLiteral("Scene B"))
                        responseData[QStringLiteral("imageData")] =
                                QStringLiteral("UUJC"); // bare base64
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.scenes().size(), 2);

    QTRY_COMPARE(client.thumbnails().value(QStringLiteral("Scene A")).toString(),
                 QStringLiteral("data:image/jpeg;base64,QUFB"));
    QTRY_COMPARE(client.thumbnails().value(QStringLiteral("Scene B")).toString(),
                 QStringLiteral("data:image/jpg;base64,UUJC"));
}

void TestObsClient::sceneListChangedPreservesThumbnailDuringRefresh()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    int screenshotResponses = 0;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetSceneList")) {
                    QJsonArray scenes;
                    scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                    QJsonObject responseData;
                    responseData[QStringLiteral("currentProgramSceneName")] =
                            QStringLiteral("Scene A");
                    responseData[QStringLiteral("scenes")] = scenes;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetSourceScreenshot")) {
                    if (screenshotResponses == 0) {
                        QJsonObject responseData;
                        responseData[QStringLiteral("imageData")] = QStringLiteral("QUFB");
                        server.sendRequestResponse(requestId, true, responseData);
                        ++screenshotResponses;
                    }
                    // Later screenshot requests go unanswered, so the thumbnail must
                    // survive the refresh on its own.
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.thumbnails().value(QStringLiteral("Scene A")).toString(),
                 QStringLiteral("data:image/jpg;base64,QUFB"));

    // Wait for the refreshed list, not just a non-empty one.
    QSignalSpy scenesSpy(&client, &ObsClient::scenesChanged);
    server.sendEvent(QStringLiteral("SceneListChanged"), { });

    QTRY_COMPARE(scenesSpy.count(), 1);
    QVERIFY(!client.scenes().isEmpty());
    QCOMPARE(client.thumbnails().value(QStringLiteral("Scene A")).toString(),
             QStringLiteral("data:image/jpg;base64,QUFB"));
}

namespace {

// Answers the scene list with one scene and records each screenshot request's
// size. Screenshots are only answered if `answerScreenshots` is set.
struct ScreenshotSizeRecorder
{
    QList<QSize> sizes;
    int requestCount = 0;
    QString lastScreenshotRequestId;

    void install(MockObsServer &server, int baseWidth = 1920, int baseHeight = 1080,
                 bool answerScreenshots = true)
    {
        QObject::connect(
                &server, &MockObsServer::requestReceived, &server,
                [this, &server, baseWidth, baseHeight, answerScreenshots](
                        const QString &type, const QString &requestId, const QJsonObject &data) {
                    if (type == QStringLiteral("GetSceneList")) {
                        QJsonArray scenes;
                        scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                        QJsonObject responseData;
                        responseData[QStringLiteral("currentProgramSceneName")] =
                                QStringLiteral("Scene A");
                        responseData[QStringLiteral("scenes")] = scenes;
                        server.sendRequestResponse(requestId, true, responseData);
                    } else if (type == QStringLiteral("GetVideoSettings")) {
                        QJsonObject responseData;
                        responseData[QStringLiteral("baseWidth")] = baseWidth;
                        responseData[QStringLiteral("baseHeight")] = baseHeight;
                        server.sendRequestResponse(requestId, true, responseData);
                    } else if (type == QStringLiteral("GetSourceScreenshot")) {
                        sizes.append(QSize(data.value(QStringLiteral("imageWidth")).toInt(),
                                           data.value(QStringLiteral("imageHeight")).toInt()));
                        ++requestCount;
                        lastScreenshotRequestId = requestId;
                        if (answerScreenshots) {
                            QJsonObject responseData;
                            responseData[QStringLiteral("imageData")] = QStringLiteral("QUFB");
                            server.sendRequestResponse(requestId, true, responseData);
                        }
                    } else {
                        server.sendRequestResponse(requestId, true, { });
                    }
                });
    }

    QSize lastSize() const { return sizes.isEmpty() ? QSize() : sizes.last(); }
};

} // namespace

void TestObsClient::requestsThumbnailsAtTheWidthTheUiAsksFor()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    ScreenshotSizeRecorder recorder;
    recorder.install(server);

    ObsClient client;
    // 300 logical px on a 2x screen, snapped up to the next step.
    client.setPreviewWidth(600);
    QCOMPARE(client.previewWidth(), 640);

    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_VERIFY(!recorder.sizes.isEmpty());

    QCOMPARE(recorder.lastSize(), QSize(640, 360));

    // Widths within the same step are not a change.
    QSignalSpy spy(&client, &ObsClient::previewWidthChanged);
    client.setPreviewWidth(590);
    client.setPreviewWidth(640);
    QCOMPARE(spy.count(), 0);
    QCOMPARE(client.previewWidth(), 640);
}

void TestObsClient::clampsThumbnailSizeAtBothExtremes()
{
    ObsClient client;

    client.setPreviewWidth(4000);
    QCOMPARE(client.previewWidth(), 1280);

    client.setPreviewWidth(1);
    QCOMPARE(client.previewWidth(), 160);

    client.setPreviewWidth(0);
    QCOMPARE(client.previewWidth(), 160);

    client.setPreviewWidth(-100);
    QCOMPARE(client.previewWidth(), 160);
}

void TestObsClient::clampsThumbnailHeightOnATallCanvas()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    // 9:16 canvas: an unclamped 1280-wide request would be 2276 tall.
    ScreenshotSizeRecorder recorder;
    recorder.install(server, 1080, 1920);

    ObsClient client;
    client.setPreviewWidth(1280);

    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_VERIFY(!recorder.sizes.isEmpty());

    // The height hits the cap; the width follows the aspect.
    QTRY_COMPARE(recorder.lastSize(), QSize(720, 1280));
}

void TestObsClient::skipsThumbnailRequestWhileTheLastIsStillInFlight()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    // Never answers screenshots, like a slow OBS or link.
    ScreenshotSizeRecorder recorder;
    recorder.install(server, 1920, 1080, false);

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(recorder.requestCount, 1);

    // After several 500 ms ticks, still only one request in flight.
    QTest::qWait(1600);
    QCOMPARE(recorder.requestCount, 1);

    // Answering lets the next tick through.
    QJsonObject responseData;
    responseData[QStringLiteral("imageData")] = QStringLiteral("QUFB");
    server.sendRequestResponse(recorder.lastScreenshotRequestId, true, responseData);

    QTRY_VERIFY(recorder.requestCount > 1);
    QCOMPARE(client.thumbnails().value(QStringLiteral("Scene A")).toString(),
             QStringLiteral("data:image/jpg;base64,QUFB"));
}

void TestObsClient::filtersNonAudioInputsFromInputList()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetInputList")) {
                    QJsonArray inputs;
                    inputs.append(makeInput(QStringLiteral("Mic"),
                                            QStringLiteral("pulse_input_capture")));
                    inputs.append(
                            makeInput(QStringLiteral("Browser"), QStringLiteral("browser_source")));
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputs")] = inputs;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.inputs().size(), 1);
    QCOMPARE(client.inputs().first().toMap().value(QStringLiteral("inputName")).toString(),
             QStringLiteral("Mic"));
}

void TestObsClient::populatesInitialInputMuteAndVolumeFromGetRequests()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetInputList")) {
                    QJsonArray inputs;
                    inputs.append(makeInput(QStringLiteral("Mic"),
                                            QStringLiteral("pulse_input_capture")));
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputs")] = inputs;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetInputMute")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputMuted")] = true;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetInputVolume")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputVolumeDb")] = -6.0;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.inputs().size(), 1);
    QTRY_VERIFY(client.inputMuted().value(QStringLiteral("Mic")).toBool());
    QTRY_COMPARE(client.inputVolumes().value(QStringLiteral("Mic")).toDouble(), -6.0);
}

void TestObsClient::inputCreatedEventTriggersInputListRefresh()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    int inputListCalls = 0;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetInputList")) {
                    QJsonArray inputs;
                    if (inputListCalls > 0)
                        inputs.append(makeInput(QStringLiteral("NewMic"),
                                                QStringLiteral("pulse_input_capture")));
                    ++inputListCalls;

                    QJsonObject responseData;
                    responseData[QStringLiteral("inputs")] = inputs;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(inputListCalls, 1);
    QCOMPARE(client.inputs().size(), 0);

    QJsonObject eventData;
    eventData[QStringLiteral("inputName")] = QStringLiteral("NewMic");
    server.sendEvent(QStringLiteral("InputCreated"), eventData);

    QTRY_COMPARE(client.inputs().size(), 1);
    QCOMPARE(client.inputs().first().toMap().value(QStringLiteral("inputName")).toString(),
             QStringLiteral("NewMic"));
}

void TestObsClient::audioControlRequestsUseCorrectTypes()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    QString lastToggleMuteInput;
    QString lastSetVolumeInput;
    double lastSetVolumeDb = 0.0;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &data) {
                if (type == QStringLiteral("GetInputList")) {
                    QJsonArray inputs;
                    inputs.append(makeInput(QStringLiteral("Mic"),
                                            QStringLiteral("pulse_input_capture")));
                    QJsonObject responseData;
                    responseData[QStringLiteral("inputs")] = inputs;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("ToggleInputMute")) {
                    lastToggleMuteInput = data.value(QStringLiteral("inputName")).toString();
                    server.sendRequestResponse(requestId, true);
                } else if (type == QStringLiteral("SetInputVolume")) {
                    lastSetVolumeInput = data.value(QStringLiteral("inputName")).toString();
                    lastSetVolumeDb = data.value(QStringLiteral("inputVolumeDb")).toDouble();
                    server.sendRequestResponse(requestId, true);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.inputs().size(), 1);

    client.toggleInputMute(QStringLiteral("Mic"));
    QTRY_COMPARE(lastToggleMuteInput, QStringLiteral("Mic"));

    client.setInputVolumeDb(QStringLiteral("Mic"), -10.5f);
    QTRY_COMPARE(lastSetVolumeInput, QStringLiteral("Mic"));
    QCOMPARE(lastSetVolumeDb, -10.5);
}

void TestObsClient::streamAndRecordStatusParsed()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetStreamStatus")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("outputActive")] = true;
                    responseData[QStringLiteral("outputTimecode")] = QStringLiteral("00:01:02.123");
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetRecordStatus")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("outputActive")] = true;
                    responseData[QStringLiteral("outputTimecode")] = QStringLiteral("00:03:04.500");
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_VERIFY(client.streaming());
    QTRY_VERIFY(client.recording());
    QTRY_COMPARE(client.streamTimecode(), QStringLiteral("00:01:02.123"));
    QTRY_COMPARE(client.recordTimecode(), QStringLiteral("00:03:04.500"));
}

// Read on connect and again when recording starts or stops.
void TestObsClient::recordDirectoryFollowsObs()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    QString directory = QStringLiteral("/home/streamer/Videos");
    int directoryRequests = 0;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetRecordDirectory")) {
                    ++directoryRequests;
                    QJsonObject responseData;
                    responseData[QStringLiteral("recordDirectory")] = directory;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.recordDirectory(), QStringLiteral("/home/streamer/Videos"));
    QCOMPARE(directoryRequests, 1);

    directory = QStringLiteral("/mnt/capture");
    QJsonObject eventData;
    eventData[QStringLiteral("outputActive")] = true;
    server.sendEvent(QStringLiteral("RecordStateChanged"), eventData);

    QTRY_COMPARE(client.recordDirectory(), QStringLiteral("/mnt/capture"));

    // Forgotten on disconnect.
    client.disconnectFromObs();
    QTRY_COMPARE(client.recordDirectory(), QString());
}

void TestObsClient::streamAndRecordControlRequestsUseCorrectTypes()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    QSet<QString> seenTypes;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                seenTypes.insert(type);
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    client.startStream();
    client.stopStream();
    client.toggleStream();
    client.startRecord();
    client.stopRecord();
    client.toggleRecord();

    QTRY_VERIFY(seenTypes.contains(QStringLiteral("StartStream")));
    QTRY_VERIFY(seenTypes.contains(QStringLiteral("StopStream")));
    QTRY_VERIFY(seenTypes.contains(QStringLiteral("ToggleStream")));
    QTRY_VERIFY(seenTypes.contains(QStringLiteral("StartRecord")));
    QTRY_VERIFY(seenTypes.contains(QStringLiteral("StopRecord")));
    QTRY_VERIFY(seenTypes.contains(QStringLiteral("ToggleRecord")));
}

namespace {

// An InputVolumeMeters entry with one channel per multiplier, each
// [magnitude, peak, inputPeak], with the magnitude at half the peak.
QJsonObject makeMeterInput(const QString &name, const QList<double> &peakMultipliers)
{
    QJsonArray channels;
    for (double peakMultiplier : peakMultipliers) {
        QJsonArray channel;
        channel.append(peakMultiplier / 2.0);
        channel.append(peakMultiplier);
        channel.append(peakMultiplier * 1.5);
        channels.append(channel);
    }

    QJsonObject input;
    input[QStringLiteral("inputName")] = name;
    input[QStringLiteral("inputLevelsMul")] = channels;
    return input;
}

QJsonObject makeMeterInput(const QString &name, double peakMultiplier)
{
    return makeMeterInput(name, QList<double>{ peakMultiplier });
}

// Read one value from the levels shape. Negative means the channel is missing.
qreal channelValue(const ObsClient &client, const QString &inputName, const QString &key,
                   int channel = 0)
{
    const QVariantList channels = client.inputLevels().value(inputName).toList();
    if (channel >= channels.size())
        return -1.0;
    return channels.at(channel).toMap().value(key).toDouble();
}

qreal channelPeak(const ObsClient &client, const QString &inputName, int channel = 0)
{
    return channelValue(client, inputName, QStringLiteral("peak"), channel);
}

qreal channelMagnitude(const ObsClient &client, const QString &inputName, int channel = 0)
{
    return channelValue(client, inputName, QStringLiteral("magnitude"), channel);
}

int channelCount(const ObsClient &client, const QString &inputName)
{
    return client.inputLevels().value(inputName).toList().size();
}

QJsonObject makeMeterEvent(const QJsonArray &inputs)
{
    QJsonObject eventData;
    eventData[QStringLiteral("inputs")] = inputs;
    return eventData;
}

} // namespace

// The client exposes the last address, so connections made with --host are
// remembered too.
void TestObsClient::exposesConnectionTarget()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    ObsClient client;
    QCOMPARE(client.host(), QString());

    QSignalSpy spy(&client, &ObsClient::connectionTargetChanged);
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QCOMPARE(client.host(), QStringLiteral("127.0.0.1"));
    QCOMPARE(client.port(), server.port());
    QCOMPARE(spy.count(), 1);

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    // Reconnecting to the same address is not a change.
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QCOMPARE(spy.count(), 1);

    // Survives the disconnect.
    client.disconnectFromObs();
    QCOMPARE(client.host(), QStringLiteral("127.0.0.1"));
    QCOMPARE(client.port(), server.port());
}

// A listening port probes true and a closed one false.
void TestObsClient::probeReportsWhatIsListening()
{
    MockObsServer server;
    QVERIFY(server.start());

    // Bound and released, so nothing listens on it.
    quint16 deadPort = 0;
    {
        MockObsServer closed;
        QVERIFY(closed.start());
        deadPort = closed.port();
    }

    ConnectionProbe probe;
    QVariantMap listening;
    listening[QStringLiteral("host")] = QStringLiteral("127.0.0.1");
    listening[QStringLiteral("port")] = server.port();
    QVariantMap dead;
    dead[QStringLiteral("host")] = QStringLiteral("127.0.0.1");
    dead[QStringLiteral("port")] = deadPort;

    const QString liveKey = ConnectionProbe::keyFor(QStringLiteral("127.0.0.1"), server.port());
    const QString deadKey = ConnectionProbe::keyFor(QStringLiteral("127.0.0.1"), deadPort);

    probe.check({ listening });
    QTRY_VERIFY(probe.reachable().contains(liveKey));
    QCOMPARE(probe.reachable().value(liveKey).toBool(), true);

    // Probing again replaces the old results.
    probe.check({ listening, dead });
    QTRY_COMPARE(probe.reachable().size(), 2);
    QCOMPARE(probe.reachable().value(liveKey).toBool(), true);
    QCOMPARE(probe.reachable().value(deadKey).toBool(), false);
    QTRY_VERIFY(!probe.busy());
}

// A refused connection (OBS's server off by default) should name the setting.
void TestObsClient::refusedConnectionSaysWhereToLook()
{
    quint16 deadPort = 0;
    {
        MockObsServer closed;
        QVERIFY(closed.start());
        deadPort = closed.port();
    }

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), deadPort, QString());

    // Generous: Windows retries refused connections for a couple of seconds.
    QTRY_VERIFY_WITH_TIMEOUT(
            client.lastError().contains(QStringLiteral("WebSocket Server Settings")), 10000);
}

// Meter events aren't part of EventSubscription::All and must be requested
// explicitly; without them the meters silently never move.
void TestObsClient::subscribesToVolumeMeterEvents()
{
    MockObsServer server;
    QVERIFY(server.start());

    int subscriptions = 0;
    connect(&server, &MockObsServer::clientConnected, &server, [&server]() { server.sendHello(); });
    connect(&server, &MockObsServer::identifyReceived, &server, [&](const QJsonObject &d) {
        subscriptions = d.value(QStringLiteral("eventSubscriptions")).toInt();
        server.sendIdentified();
    });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    constexpr int inputVolumeMeters = 1 << 16;
    QVERIFY2(subscriptions & inputVolumeMeters,
             "InputVolumeMeters must be subscribed to explicitly");
    // ...without dropping the ordinary categories.
    QCOMPARE(subscriptions & 2047, 2047);
}

void TestObsClient::appliesInputVolumeMetersEvent()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &, const QString &requestId, const QJsonObject &) {
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    // 1.0 is 0 dB, the top of the scale.
    QJsonArray inputs;
    inputs.append(makeMeterInput(QStringLiteral("Desktop Audio"), 1.0));
    // 0.001 is -60 dB, the bottom.
    inputs.append(makeMeterInput(QStringLiteral("Mic/Aux"), 0.001));
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(inputs));

    QTRY_COMPARE(channelPeak(client, QStringLiteral("Desktop Audio")), 1.0);
    QCOMPARE(channelPeak(client, QStringLiteral("Mic/Aux")), 0.0);
}

void TestObsClient::keepsALevelPerAudioChannel()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &, const QString &requestId, const QJsonObject &) {
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    // Stereo with one side at 0 dB and the other silent: two bars, not one.
    const QString name = QStringLiteral("Desktop Audio");
    QJsonArray inputs;
    inputs.append(makeMeterInput(name, QList<double>{ 1.0, 0.001 }));
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(inputs));

    QTRY_COMPARE(channelCount(client, name), 2);
    QCOMPARE(channelPeak(client, name, 0), 1.0);
    QCOMPARE(channelPeak(client, name, 1), 0.0);
}

void TestObsClient::magnitudeIsIntegratedWhereThePeakIsNot()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &, const QString &requestId, const QJsonObject &) {
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    const QString name = QStringLiteral("Desktop Audio");

    // Quiet then loud, sent back to back: the peak jumps, the magnitude barely
    // moves. Sent together so the result doesn't depend on timing.
    QJsonArray quiet;
    quiet.append(makeMeterInput(name, 0.001));
    QJsonArray loud;
    loud.append(makeMeterInput(name, 1.0));
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(quiet));
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(loud));

    QTRY_COMPARE(channelPeak(client, name), 1.0);
    const qreal magnitude = channelMagnitude(client, name);
    QVERIFY2(magnitude < 0.5, qPrintable(QStringLiteral("magnitude jumped to %1").arg(magnitude)));
}

void TestObsClient::inputLevelRisesImmediatelyAndFallsGradually()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &, const QString &requestId, const QJsonObject &) {
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    const QString name = QStringLiteral("Desktop Audio");

    // Quiet, then loud: the rise is immediate.
    QJsonArray quiet;
    quiet.append(makeMeterInput(name, 0.01));
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(quiet));
    QTRY_VERIFY(channelPeak(client, name) > 0.0);

    QJsonArray loud;
    loud.append(makeMeterInput(name, 1.0));
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(loud));
    QTRY_COMPARE(channelPeak(client, name), 1.0);

    // Then silence (no channels): the bar falls gradually, not instantly.
    QTest::qWait(500);
    QJsonArray silent;
    QJsonObject silentInput;
    silentInput[QStringLiteral("inputName")] = name;
    silentInput[QStringLiteral("inputLevelsMul")] = QJsonArray();
    silent.append(silentInput);
    server.sendEvent(QStringLiteral("InputVolumeMeters"), makeMeterEvent(silent));

    QTRY_VERIFY(channelPeak(client, name) < 1.0);
    QVERIFY(channelPeak(client, name) > 0.0);
    // The channel count is kept through an update with no channels.
    QCOMPARE(channelCount(client, name), 1);
}

void TestObsClient::parsesStatsIntoPerformanceProperties()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetStats")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("activeFps")] = 60.000001;
                    responseData[QStringLiteral("cpuUsage")] = 3.25;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.cpuUsage(), 3.25);
    QCOMPARE(client.activeFps(), 60.000001);
}

void TestObsClient::derivesStreamBitrateFromByteCounter()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    // The rate needs two samples. 125000 bytes/s is 1000 kbit/s.
    qint64 bytes = 0;
    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetStreamStatus")) {
                    bytes += 125000;
                    QJsonObject responseData;
                    responseData[QStringLiteral("outputActive")] = true;
                    responseData[QStringLiteral("outputBytes")] = double(bytes);
                    responseData[QStringLiteral("outputSkippedFrames")] = 3;
                    responseData[QStringLiteral("outputTotalFrames")] = 300;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QCOMPARE(client.streamBitrateKbps(), 0.0);

    // Samples are about a second apart; allow for timing slop.
    QTRY_VERIFY_WITH_TIMEOUT(client.streamBitrateKbps() > 0.0, 5000);
    QVERIFY2(client.streamBitrateKbps() > 500.0 && client.streamBitrateKbps() < 2000.0,
             qPrintable(QStringLiteral("bitrate was %1 kbit/s").arg(client.streamBitrateKbps())));

    QCOMPARE(client.streamSkippedFrames(), 3);
    QCOMPARE(client.streamSkippedPercent(), 1.0);
}

void TestObsClient::disconnectResetsState()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetSceneList")) {
                    QJsonArray scenes;
                    scenes.append(makeScene(QStringLiteral("Scene A"), 0));
                    QJsonObject responseData;
                    responseData[QStringLiteral("currentProgramSceneName")] =
                            QStringLiteral("Scene A");
                    responseData[QStringLiteral("scenes")] = scenes;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QTRY_COMPARE(client.scenes().size(), 1);

    client.disconnectFromObs();

    QCOMPARE(client.connectionState(), ObsClient::Disconnected);
    QVERIFY(client.scenes().isEmpty());
    QVERIFY(client.thumbnails().isEmpty());
    QVERIFY(client.sources().isEmpty());
    QVERIFY(client.sourceVisibility().isEmpty());
    QVERIFY(client.inputs().isEmpty());
    QVERIFY(client.inputMuted().isEmpty());
    QVERIFY(client.inputVolumes().isEmpty());
    QVERIFY(client.currentProgramScene().isEmpty());
    QVERIFY(!client.streaming());
    QVERIFY(!client.recording());
    QCOMPARE(client.streamTimecode(), QStringLiteral("00:00:00"));
    QCOMPARE(client.recordTimecode(), QStringLiteral("00:00:00"));
    QVERIFY(!client.studioModeEnabled());
    QVERIFY(client.previewScene().isEmpty());
    QVERIFY(client.transitions().isEmpty());
    QVERIFY(client.currentTransition().isEmpty());

    // A user-requested disconnect doesn't reconnect.
    QTest::qWait(500);
    QCOMPARE(client.connectionState(), ObsClient::Disconnected);
}

void TestObsClient::reconnectsAfterUnexpectedDisconnect()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    QVERIFY(server.clientSocket());
    server.clientSocket()->close();

    QTRY_COMPARE(client.connectionState(), ObsClient::Disconnected);

    // Allow time for the automatic reconnect and re-authentication.
    QTRY_COMPARE_WITH_TIMEOUT(client.connectionState(), ObsClient::Authenticated, 8000);
}

namespace {
quint16 closedPort()
{
    MockObsServer closed;
    if (!closed.start())
        return 0;
    return closed.port();
}
} // namespace

// A failed attempt (a typo, OBS not running) shows its error and isn't retried.
void TestObsClient::failedAttemptIsNotRetried()
{
    const quint16 port = closedPort();
    QVERIFY(port != 0);

    int attempts = 0;
    ObsClient client;
    connect(&client, &ObsClient::connectionStateChanged, &client, [&]() {
        if (client.connectionState() == ObsClient::Connecting)
            ++attempts;
    });
    client.connectToObs(QStringLiteral("127.0.0.1"), port, QString());

    QTRY_VERIFY_WITH_TIMEOUT(!client.lastError().isEmpty(), 10000);
    QTest::qWait(3500);
    QCOMPARE(attempts, 1);
    QVERIFY(!client.reconnecting());
    QCOMPARE(client.connectionState(), ObsClient::Disconnected);
}

// When a working connection drops (OBS quits), it's retried with one steady
// message, not one that's cleared and set again on every attempt.
void TestObsClient::droppedConnectionRetriesWithASteadyMessage()
{
    auto *server = new MockObsServer;
    QVERIFY(server->start());
    autoIdentify(*server);

    int attempts = 0;
    ObsClient client;
    connect(&client, &ObsClient::connectionStateChanged, &client, [&]() {
        if (client.connectionState() == ObsClient::Connecting)
            ++attempts;
    });
    client.connectToObs(QStringLiteral("127.0.0.1"), server->port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    QCOMPARE(attempts, 1);

    // OBS quits: nothing listens there any more.
    delete server;
    QTRY_VERIFY(client.reconnecting());
    QVERIFY(client.lastError().contains(QStringLiteral("Reconnecting")));

    // Waits for the attempts rather than a fixed time: on Windows each refused
    // attempt takes about two seconds on top of the three-second delay.
    QSignalSpy errorChanges(&client, &ObsClient::lastErrorChanged);
    QTRY_VERIFY_WITH_TIMEOUT(attempts >= 3, 20000);
    QCOMPARE(errorChanges.count(), 0);
    QVERIFY(client.reconnecting());

    // Closing on purpose stops it.
    client.disconnectFromObs();
    QVERIFY(!client.reconnecting());
    const int before = attempts;
    QTest::qWait(3500);
    QCOMPARE(attempts, before);
}

void TestObsClient::malformedMessageDoesNotCrash()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    QVERIFY(server.clientSocket());
    server.clientSocket()->sendTextMessage(QStringLiteral("not json at all {{{"));
    server.clientSocket()->sendTextMessage(QStringLiteral("{}"));
    server.clientSocket()->sendTextMessage(QStringLiteral("{\"op\":9999,\"d\":{}}"));

    QTest::qWait(200);
    QCOMPARE(client.connectionState(), ObsClient::Authenticated);
}

void TestObsClient::populatesStudioModeStateOnConnect()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetStudioModeEnabled")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("studioModeEnabled")] = false;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());

    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    // Wait for the answer: "off" is also the initial value.
    QTRY_COMPARE(server.answeredCount(QStringLiteral("GetStudioModeEnabled")), 1);
    QTRY_VERIFY(!client.studioModeEnabled());
    QVERIFY(client.previewScene().isEmpty());
}

// Stats are unknown until OBS answers, so the UI doesn't show zeros as
// readings.
void TestObsClient::statsAreUnknownUntilObsAnswers()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    bool answerStats = false;
    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetStats")) {
                    if (!answerStats) {
                        // Refused, as an OBS without this request would.
                        server.sendRequestResponse(requestId, false, { });
                        return;
                    }
                    QJsonObject responseData;
                    responseData[QStringLiteral("activeFps")] = 60.0;
                    responseData[QStringLiteral("cpuUsage")] = 4.5;
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    QVERIFY(!client.statsKnown());

    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    QTest::qWait(150);
    QVERIFY(!client.statsKnown());
    QCOMPARE(client.activeFps(), 0.0);

    answerStats = true;
    QTRY_VERIFY(client.statsKnown());
    QTRY_COMPARE(client.activeFps(), 60.0);

    // Unknown again after disconnecting.
    client.disconnectFromObs();
    QTRY_VERIFY(!client.statsKnown());
}

// Either field name works (the old one is deprecated).
void TestObsClient::previewSceneTakesEitherOfTheNamesObsHasUsed()
{
    for (const QString &field :
         { QStringLiteral("sceneName"), QStringLiteral("currentPreviewSceneName") }) {
        MockObsServer server;
        QVERIFY(server.start());
        autoIdentify(server);

        connect(&server, &MockObsServer::requestReceived, &server,
                [&](const QString &type, const QString &requestId, const QJsonObject &) {
                    if (type == QStringLiteral("GetStudioModeEnabled")) {
                        QJsonObject responseData;
                        responseData[QStringLiteral("studioModeEnabled")] = true;
                        server.sendRequestResponse(requestId, true, responseData);
                    } else if (type == QStringLiteral("GetCurrentPreviewScene")) {
                        QJsonObject responseData;
                        responseData[field] = QStringLiteral("Scene A");
                        server.sendRequestResponse(requestId, true, responseData);
                    } else {
                        server.sendRequestResponse(requestId, true, { });
                    }
                });

        ObsClient client;
        client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
        QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
        QTRY_COMPARE(client.previewScene(), QStringLiteral("Scene A"));
    }
}

void TestObsClient::enteringStudioModeFetchesPreviewScene()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetStudioModeEnabled")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("studioModeEnabled")] = false;
                    server.sendRequestResponse(requestId, true, responseData);
                } else if (type == QStringLiteral("GetCurrentPreviewScene")) {
                    QJsonObject responseData;
                    responseData[QStringLiteral("currentPreviewSceneName")] =
                            QStringLiteral("Scene A");
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    // Wait for the answer, or it could arrive after the event and undo it.
    QTRY_COMPARE(server.answeredCount(QStringLiteral("GetStudioModeEnabled")), 1);
    QVERIFY(!client.studioModeEnabled());

    QJsonObject eventData;
    eventData[QStringLiteral("studioModeEnabled")] = true;
    server.sendEvent(QStringLiteral("StudioModeStateChanged"), eventData);

    QTRY_VERIFY(client.studioModeEnabled());
    QTRY_COMPARE(client.previewScene(), QStringLiteral("Scene A"));

    QJsonObject disabledEventData;
    disabledEventData[QStringLiteral("studioModeEnabled")] = false;
    server.sendEvent(QStringLiteral("StudioModeStateChanged"), disabledEventData);

    QTRY_VERIFY(!client.studioModeEnabled());
    QTRY_VERIFY(client.previewScene().isEmpty());
}

void TestObsClient::appliesCurrentPreviewSceneChangedEvent()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &, const QString &requestId, const QJsonObject &) {
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    QJsonObject eventData;
    eventData[QStringLiteral("sceneName")] = QStringLiteral("Scene B");
    server.sendEvent(QStringLiteral("CurrentPreviewSceneChanged"), eventData);

    QTRY_COMPARE(client.previewScene(), QStringLiteral("Scene B"));
}

void TestObsClient::parsesTransitionList()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &) {
                if (type == QStringLiteral("GetSceneTransitionList")) {
                    QJsonObject cut;
                    cut[QStringLiteral("transitionName")] = QStringLiteral("Cut");
                    QJsonObject fade;
                    fade[QStringLiteral("transitionName")] = QStringLiteral("Fade");

                    QJsonArray transitions;
                    transitions.append(cut);
                    transitions.append(fade);

                    QJsonObject responseData;
                    responseData[QStringLiteral("transitions")] = transitions;
                    responseData[QStringLiteral("currentSceneTransitionName")] =
                            QStringLiteral("Fade");
                    server.sendRequestResponse(requestId, true, responseData);
                } else {
                    server.sendRequestResponse(requestId, true, { });
                }
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    QTRY_COMPARE(client.transitions().size(), 2);
    QCOMPARE(client.transitions().first().toString(), QStringLiteral("Cut"));
    QCOMPARE(client.transitions().last().toString(), QStringLiteral("Fade"));
    QCOMPARE(client.currentTransition(), QStringLiteral("Fade"));
}

void TestObsClient::appliesCurrentSceneTransitionChangedEvent()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &, const QString &requestId, const QJsonObject &) {
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);
    // The list's answer carries the current transition; it must not undo the
    // event.
    QTRY_COMPARE(server.answeredCount(QStringLiteral("GetSceneTransitionList")), 1);

    QJsonObject eventData;
    eventData[QStringLiteral("transitionName")] = QStringLiteral("Stinger");
    server.sendEvent(QStringLiteral("CurrentSceneTransitionChanged"), eventData);

    QTRY_COMPARE(client.currentTransition(), QStringLiteral("Stinger"));
}

void TestObsClient::studioModeControlRequestsUseCorrectTypes()
{
    MockObsServer server;
    QVERIFY(server.start());
    autoIdentify(server);

    bool lastStudioModeEnabledRequest = false;
    QString lastPreviewSceneRequest;
    QString lastTransitionNameRequest;
    QSet<QString> seenTypes;

    connect(&server, &MockObsServer::requestReceived, &server,
            [&](const QString &type, const QString &requestId, const QJsonObject &data) {
                seenTypes.insert(type);
                if (type == QStringLiteral("SetStudioModeEnabled"))
                    lastStudioModeEnabledRequest =
                            data.value(QStringLiteral("studioModeEnabled")).toBool();
                else if (type == QStringLiteral("SetCurrentPreviewScene"))
                    lastPreviewSceneRequest = data.value(QStringLiteral("sceneName")).toString();
                else if (type == QStringLiteral("SetCurrentSceneTransition"))
                    lastTransitionNameRequest =
                            data.value(QStringLiteral("transitionName")).toString();
                server.sendRequestResponse(requestId, true, { });
            });

    ObsClient client;
    client.connectToObs(QStringLiteral("127.0.0.1"), server.port(), QString());
    QTRY_COMPARE(client.connectionState(), ObsClient::Authenticated);

    client.setStudioModeEnabled(true);
    QTRY_VERIFY(lastStudioModeEnabledRequest);

    client.setCurrentPreviewScene(QStringLiteral("Scene C"));
    QTRY_COMPARE(lastPreviewSceneRequest, QStringLiteral("Scene C"));

    client.setCurrentTransition(QStringLiteral("Wipe"));
    QTRY_COMPARE(lastTransitionNameRequest, QStringLiteral("Wipe"));

    client.triggerStudioModeTransition();
    QTRY_VERIFY(seenTypes.contains(QStringLiteral("TriggerStudioModeTransition")));
}

QTEST_GUILESS_MAIN(TestObsClient)
#include "tst_ObsClient.moc"
