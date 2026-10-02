// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QWebSocket>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QJsonObject>
#include <QJsonArray>
#include <QHash>
#include <QSet>
#include <functional>

// Client for the obs-websocket 5.x protocol:
// https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md
class ObsClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(State connectionState READ connectionState NOTIFY connectionStateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

    // The address last connected or connecting to, from the form or the command
    // line.
    Q_PROPERTY(QString host READ host NOTIFY connectionTargetChanged)
    Q_PROPERTY(int port READ port NOTIFY connectionTargetChanged)

    Q_PROPERTY(QVariantList scenes READ scenes NOTIFY scenesChanged)
    // Thumbnails by scene name. Kept out of `scenes` because changing a
    // QVariantList model rebuilds every delegate in the view.
    Q_PROPERTY(QVariantMap thumbnails READ thumbnails NOTIFY thumbnailsChanged)
    Q_PROPERTY(
            QString currentProgramScene READ currentProgramScene NOTIFY currentProgramSceneChanged)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY sourcesChanged)
    // Visibility by sceneItemId (as a string); kept out of `sources` likewise.
    Q_PROPERTY(QVariantMap sourceVisibility READ sourceVisibility NOTIFY sourceVisibilityChanged)
    Q_PROPERTY(QVariantList inputs READ inputs NOTIFY inputsChanged)
    // Mute and volume by input name; kept out of `inputs` likewise.
    Q_PROPERTY(QVariantMap inputMuted READ inputMuted NOTIFY inputMutedChanged)
    Q_PROPERTY(QVariantMap inputVolumes READ inputVolumes NOTIFY inputVolumesChanged)
    // Levels by input name: a list with one {peak, magnitude} map per channel,
    // each a 0..1 fraction of a -60 dB meter.
    Q_PROPERTY(QVariantMap inputLevels READ inputLevels NOTIFY inputLevelsChanged)

    Q_PROPERTY(bool streaming READ streaming NOTIFY streamingChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(QString streamTimecode READ streamTimecode NOTIFY streamTimecodeChanged)
    Q_PROPERTY(QString recordTimecode READ recordTimecode NOTIFY recordTimecodeChanged)
    // The recording folder; empty until OBS answers.
    Q_PROPERTY(QString recordDirectory READ recordDirectory NOTIFY recordDirectoryChanged)

    // Performance numbers, sharing one signal since they update together.
    // statsKnown is false until OBS has answered GetStats; before that the
    // numbers are zero, not real readings.
    Q_PROPERTY(bool statsKnown READ statsKnown NOTIFY statsChanged)
    Q_PROPERTY(qreal activeFps READ activeFps NOTIFY statsChanged)
    Q_PROPERTY(qreal cpuUsage READ cpuUsage NOTIFY statsChanged)
    // Derived from GetStreamStatus's byte counter; zero when not streaming.
    Q_PROPERTY(qreal streamBitrateKbps READ streamBitrateKbps NOTIFY statsChanged)
    Q_PROPERTY(int streamSkippedFrames READ streamSkippedFrames NOTIFY statsChanged)
    Q_PROPERTY(qreal streamSkippedPercent READ streamSkippedPercent NOTIFY statsChanged)

    // Canvas aspect ratio, which thumbnails and preview boxes follow. 16:9
    // until OBS answers.
    Q_PROPERTY(qreal videoAspect READ videoAspect NOTIFY videoAspectChanged)

    // Thumbnail width to request, in device pixels. Set by the UI to its
    // largest thumbnail box; the setter clamps and snaps it.
    Q_PROPERTY(int previewWidth READ previewWidth WRITE setPreviewWidth NOTIFY previewWidthChanged)

    Q_PROPERTY(bool studioModeEnabled READ studioModeEnabled NOTIFY studioModeEnabledChanged)
    Q_PROPERTY(QString previewScene READ previewScene NOTIFY previewSceneChanged)
    Q_PROPERTY(QVariantList transitions READ transitions NOTIFY transitionsChanged)
    Q_PROPERTY(QString currentTransition READ currentTransition NOTIFY currentTransitionChanged)

public:
    enum State { Disconnected, Connecting, Connected, Authenticated };
    Q_ENUM(State)

    explicit ObsClient(QObject *parent = nullptr);
    ~ObsClient() override;

    State connectionState() const { return m_state; }
    QString lastError() const { return m_lastError; }

    QString host() const { return m_host; }
    int port() const { return m_port; }

    QVariantList scenes() const { return m_scenes; }
    QVariantMap thumbnails() const { return m_thumbnails; }
    QString currentProgramScene() const { return m_currentProgramScene; }
    QVariantList sources() const { return m_sources; }
    QVariantMap sourceVisibility() const { return m_sourceVisibility; }
    QVariantList inputs() const { return m_inputs; }
    QVariantMap inputMuted() const { return m_inputMuted; }
    QVariantMap inputVolumes() const { return m_inputVolumes; }
    QVariantMap inputLevels() const { return m_inputLevels; }

    bool statsKnown() const { return m_statsKnown; }
    qreal activeFps() const { return m_activeFps; }
    qreal cpuUsage() const { return m_cpuUsage; }
    qreal streamBitrateKbps() const { return m_streamBitrateKbps; }
    int streamSkippedFrames() const { return m_streamSkippedFrames; }
    qreal streamSkippedPercent() const { return m_streamSkippedPercent; }

    bool streaming() const { return m_streaming; }
    bool recording() const { return m_recording; }
    QString streamTimecode() const { return m_streamTimecode; }
    QString recordTimecode() const { return m_recordTimecode; }
    QString recordDirectory() const { return m_recordDirectory; }

    qreal videoAspect() const { return m_videoAspect; }
    int previewWidth() const { return m_previewWidth; }

    bool studioModeEnabled() const { return m_studioModeEnabled; }
    QString previewScene() const { return m_previewScene; }
    QVariantList transitions() const { return m_transitions; }
    QString currentTransition() const { return m_currentTransition; }

    // Public for the tests.
    static QString computeAuthResponse(const QString &password, const QString &salt,
                                       const QString &challenge);

public slots:
    void connectToObs(const QString &host, int port, const QString &password);
    void disconnectFromObs();

    void setCurrentProgramScene(const QString &sceneName);
    void setSceneItemEnabled(const QString &sceneName, int sceneItemId, bool enabled);

    void toggleInputMute(const QString &inputName);
    void setInputVolumeDb(const QString &inputName, float volumeDb);

    void startStream();
    void stopStream();
    void toggleStream();

    void startRecord();
    void stopRecord();
    void toggleRecord();

    void setPreviewWidth(int width);

    void setStudioModeEnabled(bool enabled);
    void setCurrentPreviewScene(const QString &sceneName);
    void triggerStudioModeTransition();
    void setCurrentTransition(const QString &transitionName);

signals:
    void connectionStateChanged();
    void lastErrorChanged();
    void connectionTargetChanged();
    void scenesChanged();
    void thumbnailsChanged();
    void currentProgramSceneChanged();
    void sourcesChanged();
    void sourceVisibilityChanged();
    void inputsChanged();
    void inputMutedChanged();
    void inputVolumesChanged();
    void inputLevelsChanged();
    void statsChanged();
    void streamingChanged();
    void recordingChanged();
    void streamTimecodeChanged();
    void recordTimecodeChanged();
    void recordDirectoryChanged();

    void videoAspectChanged();
    void previewWidthChanged();

    void studioModeEnabledChanged();
    void previewSceneChanged();
    void transitionsChanged();
    void currentTransitionChanged();

private:
    using ResponseCallback =
            std::function<void(bool ok, const QJsonObject &responseData, const QString &comment)>;

    void setState(State state);
    void setLastError(const QString &error);

    void sendRequest(const QString &requestType, const QJsonObject &requestData = { },
                     ResponseCallback callback = nullptr);

    void onTextMessageReceived(const QString &message);
    void onSocketError(QAbstractSocket::SocketError error);
    void onSocketDisconnected();

    void handleHello(const QJsonObject &d);
    void handleIdentified(const QJsonObject &d);
    void handleEvent(const QJsonObject &d);
    void handleRequestResponse(const QJsonObject &d);

    void requestSceneList();
    void requestSceneItemList(const QString &sceneName);
    void requestInputList();
    void requestInputState(const QString &inputName);
    void requestStreamStatus();
    void requestRecordStatus();
    void requestRecordDirectory();
    void requestStats();

    void applyInputLevels(const QJsonArray &inputs);

    void requestVideoSettings();
    void requestSceneScreenshot(const QString &sceneName);
    void updateSceneThumbnail(const QString &sceneName, const QString &imageData);

    void requestStudioModeState();
    void requestCurrentPreviewScene();
    void requestTransitionList();

    void scheduleReconnect();

    QWebSocket m_socket;
    State m_state = Disconnected;
    QString m_lastError;

    QString m_host;
    int m_port = 4455;
    QString m_password;
    bool m_userRequestedDisconnect = false;

    QHash<QString, ResponseCallback> m_pendingRequests;

    QVariantList m_scenes;
    QVariantMap m_thumbnails;
    QString m_currentProgramScene;
    QVariantList m_sources;
    QVariantMap m_sourceVisibility;
    QVariantList m_inputs;
    QVariantMap m_inputMuted;
    QVariantMap m_inputVolumes;
    QVariantMap m_inputLevels;

    bool m_statsKnown = false;
    qreal m_activeFps = 0.0;
    qreal m_cpuUsage = 0.0;
    qreal m_streamBitrateKbps = 0.0;
    int m_streamSkippedFrames = 0;
    qreal m_streamSkippedPercent = 0.0;
    // Previous byte counter sample for the bitrate; -1 means none yet, and is
    // reset when the stream stops.
    qint64 m_lastStreamBytes = -1;
    qint64 m_lastStreamBytesMs = 0;
    // For scaling meter decay by elapsed time.
    qint64 m_lastLevelUpdateMs = 0;

    bool m_streaming = false;
    bool m_recording = false;
    QString m_streamTimecode = QStringLiteral("00:00:00");
    QString m_recordTimecode = QStringLiteral("00:00:00");
    QString m_recordDirectory;

    qreal m_videoAspect = 16.0 / 9.0;
    int m_previewWidth = 0; // Set in the constructor.
    // Scenes with a screenshot request in flight.
    QSet<QString> m_scenesAwaitingScreenshot;

    bool m_studioModeEnabled = false;
    QString m_previewScene;
    QVariantList m_transitions;
    QString m_currentTransition;

    QTimer m_statusTimer;
    QTimer m_reconnectTimer;
    QTimer m_previewTimer;
    int m_previewRoundRobinIndex = 0;
    int m_previewTickCounter = 0;
};
