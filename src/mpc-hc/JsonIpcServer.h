/*
 * JSON IPC server for MPC-HC.
 *
 * The transport is intentionally local-only: each process exposes a named pipe
 * whose ACL grants access only to the Windows account that launched MPC-HC.
 */

#pragma once

#include <atomic>
#include <climits>

#define WM_JSON_IPC_REQUEST (WM_APP + 904)

constexpr int MPC_JSON_IPC_VERSION = 1;

enum class JsonIpcMethod {
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

struct JsonIpcSnapshot {
    CStringW state;
    CStringW file;
    CStringW renderer;
    CStringW decoder;
    CStringW hardwareDevice;
    double positionSeconds = 0.0;
    double durationSeconds = 0.0;
    double playbackRate = 1.0;
    int volume = 0;
    bool muted = false;
    int audioTrack = -1;
    int subtitleTrack = -1;
    int rendererId = -1;
    int framesDrawn = -1;
    int framesDropped = -1;
    int jitterMs = INT_MIN;
    int averageSyncOffsetMs = INT_MIN;
};

struct JsonIpcRequest {
    explicit JsonIpcRequest(JsonIpcMethod requestMethod)
        : method(requestMethod)
        , doneEvent(CreateEventW(nullptr, TRUE, FALSE, nullptr))
    {
    }

    ~JsonIpcRequest()
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

    JsonIpcMethod method;
    CStringW textValue;
    double numberValue = 0.0;
    int integerValue = 0;
    bool success = false;
    int errorCode = -32000;
    CStringA errorMessage;
    JsonIpcSnapshot snapshot;
    HANDLE doneEvent = nullptr;
    std::atomic<long> references { 2 }; // transport thread + UI thread
};

class CJsonIpcServer
{
public:
    CJsonIpcServer() = default;
    ~CJsonIpcServer();

    bool Start(HWND targetWindow);
    void Stop();
    CStringW GetPipeName() const { return m_pipeName; }

private:
    static DWORD WINAPI ThreadProc(LPVOID parameter);
    DWORD Run();
    bool ServeClient(HANDLE pipe);
    CStringA ProcessRequest(const CStringA& line);

    HWND m_targetWindow = nullptr;
    CStringW m_pipeName;
    HANDLE m_stopEvent = nullptr;
    HANDLE m_thread = nullptr;
    std::atomic<HANDLE> m_activePipe { INVALID_HANDLE_VALUE };
};
