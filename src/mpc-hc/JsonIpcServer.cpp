/*
 * JSON IPC server for MPC-HC.
 */

#include "stdafx.h"
#include "JsonIpcServer.h"

#include <sddl.h>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include "../DSUtil/DSUtil.h"
#include "../thirdparty/rapidjson/include/rapidjson/document.h"
#include "../thirdparty/rapidjson/include/rapidjson/stringbuffer.h"
#include "../thirdparty/rapidjson/include/rapidjson/writer.h"

namespace {
    constexpr DWORD kMaxRequestBytes = 64 * 1024;
    constexpr DWORD kUiRequestTimeoutMs = 10000;

    CStringA MakeError(int code, LPCSTR message, bool hasId = false, int64_t id = 0)
    {
        rapidjson::StringBuffer buffer;
        rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
        writer.StartObject();
        if (hasId) {
            writer.Key("id");
            writer.Int64(id);
        }
        writer.Key("error");
        writer.StartObject();
        writer.Key("code");
        writer.Int(code);
        writer.Key("message");
        writer.String(message ? message : "Unknown error");
        writer.EndObject();
        writer.EndObject();
        return CStringA(buffer.GetString(), static_cast<int>(buffer.GetSize()));
    }

    CStringA SerializeReply(const JsonIpcRequest& request, bool hasId, int64_t id)
    {
        if (!request.success) {
            return MakeError(request.errorCode,
                             request.errorMessage.IsEmpty() ? "Request failed" : request.errorMessage.GetString(),
                             hasId, id);
        }

        rapidjson::StringBuffer buffer;
        rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
        writer.StartObject();
        if (hasId) {
            writer.Key("id");
            writer.Int64(id);
        }
        writer.Key("result");
        writer.StartObject();
        writer.Key("apiVersion");
        writer.Int(MPC_JSON_IPC_VERSION);

        if (request.method == JsonIpcMethod::GET_STATE || request.method == JsonIpcMethod::GET_DIAGNOSTICS) {
            const JsonIpcSnapshot& s = request.snapshot;
            const CStringA state = UTF16To8(s.state);
            const CStringA file = UTF16To8(s.file);
            writer.Key("state");
            writer.String(state.GetString(), state.GetLength());
            writer.Key("position");
            writer.Double(s.positionSeconds);
            writer.Key("duration");
            writer.Double(s.durationSeconds);
            writer.Key("rate");
            writer.Double(s.playbackRate);
            writer.Key("volume");
            writer.Int(s.volume);
            writer.Key("muted");
            writer.Bool(s.muted);
            writer.Key("audioTrack");
            writer.Int(s.audioTrack);
            writer.Key("subtitleTrack");
            writer.Int(s.subtitleTrack);
            writer.Key("file");
            writer.String(file.GetString(), file.GetLength());

            if (request.method == JsonIpcMethod::GET_DIAGNOSTICS) {
                const CStringA renderer = UTF16To8(s.renderer);
                writer.Key("renderer");
                writer.StartObject();
                writer.Key("id");
                writer.Int(s.rendererId);
                writer.Key("name");
                writer.String(renderer.GetString(), renderer.GetLength());
                if (!s.decoder.IsEmpty()) {
                    const CStringA decoder = UTF16To8(s.decoder);
                    writer.Key("decoder");
                    writer.String(decoder.GetString(), decoder.GetLength());
                }
                if (!s.hardwareDevice.IsEmpty()) {
                    const CStringA hardwareDevice = UTF16To8(s.hardwareDevice);
                    writer.Key("hardwareDevice");
                    writer.String(hardwareDevice.GetString(), hardwareDevice.GetLength());
                }
                if (s.framesDrawn >= 0) {
                    writer.Key("framesDrawn");
                    writer.Int(s.framesDrawn);
                }
                if (s.framesDropped >= 0) {
                    writer.Key("framesDropped");
                    writer.Int(s.framesDropped);
                }
                if (s.jitterMs != INT_MIN) {
                    writer.Key("jitterMs");
                    writer.Int(s.jitterMs);
                }
                if (s.averageSyncOffsetMs != INT_MIN) {
                    writer.Key("averageSyncOffsetMs");
                    writer.Int(s.averageSyncOffsetMs);
                }
                writer.EndObject();
            }
        } else {
            writer.Key("ok");
            writer.Bool(true);
        }

        writer.EndObject();
        writer.EndObject();
        return CStringA(buffer.GetString(), static_cast<int>(buffer.GetSize()));
    }

    bool BuildCurrentUserSecurityAttributes(SECURITY_ATTRIBUTES& attributes, PSECURITY_DESCRIPTOR& descriptor)
    {
        descriptor = nullptr;
        HANDLE token = nullptr;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
            return false;
        }

        DWORD size = 0;
        GetTokenInformation(token, TokenUser, nullptr, 0, &size);
        if (!size) {
            CloseHandle(token);
            return false;
        }

        std::vector<BYTE> buffer(size);
        if (!GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
            CloseHandle(token);
            return false;
        }
        CloseHandle(token);

        const TOKEN_USER* tokenUser = reinterpret_cast<const TOKEN_USER*>(buffer.data());
        LPWSTR sid = nullptr;
        if (!ConvertSidToStringSidW(tokenUser->User.Sid, &sid)) {
            return false;
        }

        CStringW sddl;
        sddl.Format(L"D:P(A;;GA;;;%s)", sid);
        LocalFree(sid);

        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1, &descriptor, nullptr)) {
            return false;
        }

        attributes.nLength = sizeof(attributes);
        attributes.lpSecurityDescriptor = descriptor;
        attributes.bInheritHandle = FALSE;
        return true;
    }

    bool WriteLine(HANDLE pipe, const CStringA& line)
    {
        CStringA framed(line);
        framed += '\n';
        const BYTE* data = reinterpret_cast<const BYTE*>(framed.GetString());
        DWORD remaining = static_cast<DWORD>(framed.GetLength());
        while (remaining) {
            DWORD written = 0;
            if (!WriteFile(pipe, data, remaining, &written, nullptr) || written == 0) {
                return false;
            }
            data += written;
            remaining -= written;
        }
        return true;
    }
}

CJsonIpcServer::~CJsonIpcServer()
{
    Stop();
}

bool CJsonIpcServer::Start(HWND targetWindow)
{
    Stop();
    if (!targetWindow || !IsWindow(targetWindow)) {
        return false;
    }

    m_targetWindow = targetWindow;
    m_pipeName.Format(L"\\\\.\\pipe\\MPC-HC-json-%lu", GetCurrentProcessId());
    m_stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!m_stopEvent) {
        return false;
    }

    m_thread = CreateThread(nullptr, 0, ThreadProc, this, 0, nullptr);
    if (!m_thread) {
        CloseHandle(m_stopEvent);
        m_stopEvent = nullptr;
        return false;
    }
    return true;
}

void CJsonIpcServer::Stop()
{
    if (!m_thread) {
        if (m_stopEvent) {
            CloseHandle(m_stopEvent);
            m_stopEvent = nullptr;
        }
        return;
    }

    SetEvent(m_stopEvent);
    CancelSynchronousIo(m_thread);

    // Connecting to our own listener also wakes a synchronous ConnectNamedPipe call on
    // systems where CancelSynchronousIo does not interrupt it immediately.
    HANDLE wake = CreateFileW(m_pipeName, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
    if (wake != INVALID_HANDLE_VALUE) {
        CloseHandle(wake);
    }

    WaitForSingleObject(m_thread, 5000);
    CloseHandle(m_thread);
    m_thread = nullptr;
    CloseHandle(m_stopEvent);
    m_stopEvent = nullptr;
    m_targetWindow = nullptr;
    m_activePipe.store(INVALID_HANDLE_VALUE, std::memory_order_release);
}

DWORD WINAPI CJsonIpcServer::ThreadProc(LPVOID parameter)
{
    return static_cast<CJsonIpcServer*>(parameter)->Run();
}

DWORD CJsonIpcServer::Run()
{
    SECURITY_ATTRIBUTES attributes = {};
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!BuildCurrentUserSecurityAttributes(attributes, descriptor)) {
        return ERROR_ACCESS_DENIED;
    }

    while (WaitForSingleObject(m_stopEvent, 0) == WAIT_TIMEOUT) {
        HANDLE pipe = CreateNamedPipeW(
            m_pipeName,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            1,
            kMaxRequestBytes,
            kMaxRequestBytes,
            0,
            &attributes);
        if (pipe == INVALID_HANDLE_VALUE) {
            LocalFree(descriptor);
            return GetLastError();
        }
        m_activePipe.store(pipe, std::memory_order_release);

        const BOOL connected = ConnectNamedPipe(pipe, nullptr)
            ? TRUE
            : (GetLastError() == ERROR_PIPE_CONNECTED);
        if (connected && WaitForSingleObject(m_stopEvent, 0) == WAIT_TIMEOUT) {
            ServeClient(pipe);
        }

        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        m_activePipe.store(INVALID_HANDLE_VALUE, std::memory_order_release);
    }

    LocalFree(descriptor);
    return ERROR_SUCCESS;
}

bool CJsonIpcServer::ServeClient(HANDLE pipe)
{
    std::string pending;
    pending.reserve(4096);
    char chunk[4096];

    while (WaitForSingleObject(m_stopEvent, 0) == WAIT_TIMEOUT) {
        DWORD read = 0;
        if (!ReadFile(pipe, chunk, sizeof(chunk), &read, nullptr) || read == 0) {
            return false;
        }
        pending.append(chunk, chunk + read);

        size_t newline = std::string::npos;
        while ((newline = pending.find('\n')) != std::string::npos) {
            std::string line = pending.substr(0, newline);
            pending.erase(0, newline + 1);
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            if (line.empty()) {
                continue;
            }
            if (line.size() > kMaxRequestBytes) {
                WriteLine(pipe, MakeError(-32600, "Request exceeds 64 KiB limit"));
                return false;
            }
            if (!WriteLine(pipe, ProcessRequest(CStringA(line.data(), static_cast<int>(line.size()))))) {
                return false;
            }
        }

        if (pending.size() > kMaxRequestBytes) {
            WriteLine(pipe, MakeError(-32600, "Request exceeds 64 KiB limit"));
            return false;
        }
    }
    return false;
}

CStringA CJsonIpcServer::ProcessRequest(const CStringA& line)
{
    rapidjson::Document document;
    document.Parse(line.GetString(), line.GetLength());
    if (document.HasParseError() || !document.IsObject()) {
        return MakeError(-32700, "Invalid JSON");
    }

    const bool hasId = document.HasMember("id") && document["id"].IsInt64();
    const int64_t id = hasId ? document["id"].GetInt64() : 0;
    if (!document.HasMember("method") || !document["method"].IsString()) {
        return MakeError(-32600, "Missing string method", hasId, id);
    }

    const CStringA method(document["method"].GetString());
    JsonIpcMethod parsedMethod;
    if (method == "player.getState") parsedMethod = JsonIpcMethod::GET_STATE;
    else if (method == "player.getDiagnostics") parsedMethod = JsonIpcMethod::GET_DIAGNOSTICS;
    else if (method == "player.play") parsedMethod = JsonIpcMethod::PLAY;
    else if (method == "player.pause") parsedMethod = JsonIpcMethod::PAUSE;
    else if (method == "player.stop") parsedMethod = JsonIpcMethod::STOP;
    else if (method == "player.seek") parsedMethod = JsonIpcMethod::SEEK;
    else if (method == "player.setRate") parsedMethod = JsonIpcMethod::SET_RATE;
    else if (method == "player.setVolume") parsedMethod = JsonIpcMethod::SET_VOLUME;
    else if (method == "player.setMute") parsedMethod = JsonIpcMethod::SET_MUTE;
    else if (method == "player.setAudioTrack") parsedMethod = JsonIpcMethod::SET_AUDIO_TRACK;
    else if (method == "player.setSubtitleTrack") parsedMethod = JsonIpcMethod::SET_SUBTITLE_TRACK;
    else if (method == "player.open") parsedMethod = JsonIpcMethod::OPEN_MEDIA;
    else return MakeError(-32601, "Unknown method", hasId, id);

    std::unique_ptr<JsonIpcRequest, void(*)(JsonIpcRequest*)> request(
        new JsonIpcRequest(parsedMethod), [](JsonIpcRequest* p) { p->Release(); });
    if (!request->doneEvent) {
        request->Release(); // UI ownership was never posted
        return MakeError(-32000, "Unable to create request event", hasId, id);
    }

    const rapidjson::Value* params = document.HasMember("params") && document["params"].IsObject()
        ? &document["params"] : nullptr;
    if (parsedMethod == JsonIpcMethod::SEEK || parsedMethod == JsonIpcMethod::SET_RATE) {
        const char* key = parsedMethod == JsonIpcMethod::SEEK ? "position" : "rate";
        if (!params || !params->HasMember(key) || !(*params)[key].IsNumber()) {
            request->Release();
            return MakeError(-32602, "Missing numeric parameter", hasId, id);
        }
        request->numberValue = (*params)[key].GetDouble();
        if (!std::isfinite(request->numberValue)) {
            request->Release();
            return MakeError(-32602, "Numeric parameter must be finite", hasId, id);
        }
    } else if (parsedMethod == JsonIpcMethod::SET_VOLUME || parsedMethod == JsonIpcMethod::SET_MUTE
            || parsedMethod == JsonIpcMethod::SET_AUDIO_TRACK || parsedMethod == JsonIpcMethod::SET_SUBTITLE_TRACK) {
        const char* key = parsedMethod == JsonIpcMethod::SET_VOLUME ? "volume"
                        : parsedMethod == JsonIpcMethod::SET_MUTE ? "muted"
                        : "index";
        if (!params || !params->HasMember(key)) {
            request->Release();
            return MakeError(-32602, "Missing parameter", hasId, id);
        }
        if (parsedMethod == JsonIpcMethod::SET_MUTE) {
            if (!(*params)[key].IsBool()) {
                request->Release();
                return MakeError(-32602, "Muted must be boolean", hasId, id);
            }
            request->integerValue = (*params)[key].GetBool() ? 1 : 0;
        } else {
            if (!(*params)[key].IsInt()) {
                request->Release();
                return MakeError(-32602, "Parameter must be an integer", hasId, id);
            }
            request->integerValue = (*params)[key].GetInt();
        }
    } else if (parsedMethod == JsonIpcMethod::OPEN_MEDIA) {
        if (!params || !params->HasMember("path") || !(*params)["path"].IsString()) {
            request->Release();
            return MakeError(-32602, "Missing string path", hasId, id);
        }
        const rapidjson::Value& pathValue = (*params)["path"];
        if (memchr(pathValue.GetString(), '\0', pathValue.GetStringLength()) != nullptr) {
            request->Release();
            return MakeError(-32602, "Path contains an embedded NUL", hasId, id);
        }
        request->textValue = UTF8To16(pathValue.GetString());
        if (request->textValue.IsEmpty() || request->textValue.GetLength() > 32767) {
            request->Release();
            return MakeError(-32602, "Path is empty or too long", hasId, id);
        }
    }

    JsonIpcRequest* raw = request.get();
    if (!PostMessageW(m_targetWindow, WM_JSON_IPC_REQUEST, 0, reinterpret_cast<LPARAM>(raw))) {
        request->Release();
        return MakeError(-32000, "Player window is unavailable", hasId, id);
    }

    HANDLE waits[2] = { raw->doneEvent, m_stopEvent };
    const DWORD wait = WaitForMultipleObjects(_countof(waits), waits, FALSE, kUiRequestTimeoutMs);
    if (wait != WAIT_OBJECT_0) {
        return MakeError(-32001, "Player did not answer within 10 seconds", hasId, id);
    }

    return SerializeReply(*raw, hasId, id);
}
