/*
 * JSON IPC server for MPC-HC.
 *
 * The transport is intentionally local-only: each process exposes a named pipe
 * whose ACL grants access only to the Windows account that launched MPC-HC.
 */

#pragma once

#include <atomic>
#include <climits>
#include "PlayerControlService.h"

#define WM_JSON_IPC_REQUEST (WM_APP + 904)

constexpr int MPC_JSON_IPC_VERSION = 1;

struct JsonIpcRequest {
    explicit JsonIpcRequest(PlayerControlMethod requestMethod)
        : control(requestMethod)
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

    PlayerControlRequest control;
    PlayerControlResult result;
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
