/*
 * Transport-independent player control/state service.
 */

#pragma once

#include <atomic>
#include <climits>

#define WM_PLAYER_CONTROL_REQUEST (WM_APP + 905)

enum class PlayerNetworkState {
    NONE,
    CONNECTING,
    READY,
    BUFFERING,
    RETRY_WAIT,
    RECONNECTING,
    FAILED,
};

enum class PlayerControlMethod {
    GET_STATE,
    GET_DIAGNOSTICS,
    PLAY,
    PAUSE,
    STOP,
    QUIT,
    SEEK,
    SET_RATE,
    SET_VOLUME,
    SET_MUTE,
    SET_AUDIO_TRACK,
    SET_SUBTITLE_TRACK,
    OPEN_MEDIA,
};

struct PlayerStateSnapshot {
    CStringW state;
    CStringW file;
    CStringW renderer;
    CStringW decoder;
    CStringW hardwareDevice;
    CStringW networkState;
    double positionSeconds = 0.0;
    double durationSeconds = 0.0;
    double playbackRate = 1.0;
    int mediaState = -1;
    int volume = 0;
    bool muted = false;
    bool buffering = false;
    int audioTrack = -1;
    int subtitleTrack = -1;
    int rendererId = -1;
    int networkRetryCount = 0;
    long networkError = 0;
    int framesDrawn = -1;
    int framesDropped = -1;
    int jitterMs = INT_MIN;
    int averageSyncOffsetMs = INT_MIN;
};

struct PlayerControlRequest {
    explicit PlayerControlRequest(PlayerControlMethod requestMethod = PlayerControlMethod::GET_STATE)
        : method(requestMethod)
    {
    }

    PlayerControlMethod method;
    CStringW textValue;
    double numberValue = 0.0;
    int integerValue = 0;
};

struct PlayerControlResult {
    bool success = false;
    int errorCode = -32000;
    CStringA errorMessage;
    PlayerStateSnapshot snapshot;
};

struct PlayerControlDispatch {
    explicit PlayerControlDispatch(const PlayerControlRequest& value)
        : request(value)
        , doneEvent(CreateEventW(nullptr, TRUE, FALSE, nullptr))
    {
    }

    ~PlayerControlDispatch()
    {
        if (doneEvent) {
            CloseHandle(doneEvent);
        }
    }

    void Release()
    {
        if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            delete this;
        }
    }

    PlayerControlRequest request;
    PlayerControlResult result;
    HANDLE doneEvent = nullptr;
    std::atomic<long> references { 2 }; // caller + UI thread
};

class CMainFrame;

class CPlayerControlService
{
public:
    void Attach(CMainFrame* frame) { m_frame = frame; }
    void Execute(const PlayerControlRequest& request, PlayerControlResult& result);

private:
    void Fail(PlayerControlResult& result, int code, LPCSTR message) const;
    void FillState(PlayerStateSnapshot& snapshot) const;
    void FillDiagnostics(PlayerStateSnapshot& snapshot) const;
    static LPCWSTR RendererName(int renderer);

    CMainFrame* m_frame = nullptr;
};
