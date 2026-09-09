/*
 * Transport-independent player control/state service.
 */

#include "stdafx.h"
#include "PlayerControlService.h"

#include "FGFilterLAV.h"
#include "MainFrm.h"
#include <DSUtil.h>


static LPCWSTR PlayerNetworkStateName(PlayerNetworkState state)
{
    switch (state) {
        case PlayerNetworkState::NONE:         return L"none";
        case PlayerNetworkState::CONNECTING:   return L"connecting";
        case PlayerNetworkState::READY:        return L"ready";
        case PlayerNetworkState::BUFFERING:    return L"buffering";
        case PlayerNetworkState::RETRY_WAIT:   return L"retry-wait";
        case PlayerNetworkState::RECONNECTING: return L"reconnecting";
        case PlayerNetworkState::FAILED:       return L"failed";
        default:                               return L"unknown";
    }
}

void CPlayerControlService::Fail(PlayerControlResult& result, int code, LPCSTR message) const
{
    result.success = false;
    result.errorCode = code;
    result.errorMessage = message;
}

LPCWSTR CPlayerControlService::RendererName(int renderer)
{
    switch (renderer) {
        case VIDRNDT_DS_VMR7:           return L"VMR-7";
        case VIDRNDT_DS_OVERLAYMIXER:   return L"Overlay Mixer";
        case VIDRNDT_DS_VMR9WINDOWED:   return L"VMR-9 Windowed";
        case VIDRNDT_DS_VMR9RENDERLESS: return L"VMR-9 Renderless";
        case VIDRNDT_DS_DXR:            return L"Haali Video Renderer";
        case VIDRNDT_DS_NULL_COMP:      return L"Null Renderer";
        case VIDRNDT_DS_NULL_UNCOMP:    return L"Null Renderer (uncompressed)";
        case VIDRNDT_DS_EVR:            return L"EVR";
        case VIDRNDT_DS_EVR_CUSTOM:     return L"EVR Custom Presenter";
        case VIDRNDT_DS_MADVR:          return L"madVR";
        case VIDRNDT_DS_SYNC:           return L"Sync Renderer";
        case VIDRNDT_DS_MPCVR:          return L"MPC Video Renderer";
        default:                        return L"Unknown";
    }
}

void CPlayerControlService::FillState(PlayerStateSnapshot& snapshot) const
{
    if (!m_frame) {
        snapshot.state = L"closed";
        return;
    }

    const OAFilterState mediaState = m_frame->GetMediaState();
    snapshot.mediaState = static_cast<int>(mediaState);
    snapshot.buffering = m_frame->m_bBuffering;
    if (m_frame->GetLoadState() != MLS::LOADED) {
        snapshot.state = L"closed";
    } else if (snapshot.buffering) {
        snapshot.state = L"buffering";
    } else {
        switch (mediaState) {
            case State_Running: snapshot.state = L"playing"; break;
            case State_Paused:  snapshot.state = L"paused"; break;
            case State_Stopped: snapshot.state = L"stopped"; break;
            default:            snapshot.state = L"changing"; break;
        }
    }

    snapshot.positionSeconds = m_frame->GetPos() / 10000000.0;
    snapshot.durationSeconds = m_frame->GetDur() / 10000000.0;
    snapshot.playbackRate = m_frame->m_dSpeedRate;
    snapshot.volume = m_frame->GetVolume();
    snapshot.muted = m_frame->IsMuted();
    snapshot.audioTrack = m_frame->GetCurrentAudioTrackIdx();
    snapshot.subtitleTrack = m_frame->GetCurrentSubtitleTrackIdx();
    snapshot.file = m_frame->GetFileName();
    const PlayerNetworkState networkState = static_cast<PlayerNetworkState>(
        m_frame->m_networkConnectionState.load(std::memory_order_acquire));
    snapshot.networkState = PlayerNetworkStateName(networkState);
    snapshot.networkRetryCount = m_frame->m_networkRetryCount.load(std::memory_order_acquire);
    snapshot.networkError = m_frame->m_lastNetworkError.load(std::memory_order_acquire);
}

void CPlayerControlService::FillDiagnostics(PlayerStateSnapshot& snapshot) const
{
    if (!m_frame) {
        return;
    }

    const CAppSettings& settings = AfxGetAppSettings();
    snapshot.rendererId = settings.iDSVideoRendererType;
    snapshot.renderer = RendererName(settings.iDSVideoRendererType);

    if (m_frame->m_pGB) {
        BeginEnumFilters(m_frame->m_pGB, pEF, pBF) {
            CComQIPtr<ILAVVideoStatus> lavStatus = pBF;
            if (lavStatus) {
                if (LPCWSTR decoder = lavStatus->GetActiveDecoderName()) {
                    snapshot.decoder = decoder;
                }
                CComBSTR device;
                if (SUCCEEDED(lavStatus->GetHWAccelActiveDevice(&device)) && device.Length() > 0) {
                    snapshot.hardwareDevice.SetString(device, device.Length());
                }
                break;
            }
        }
        EndEnumFilters;
    }

    if (m_frame->m_pQP) {
        int value = 0;
        if (SUCCEEDED(m_frame->m_pQP->get_FramesDrawn(&value))) {
            snapshot.framesDrawn = value;
        }
        if (SUCCEEDED(m_frame->m_pQP->get_FramesDroppedInRenderer(&value))) {
            snapshot.framesDropped = value;
        }
        if (SUCCEEDED(m_frame->m_pQP->get_Jitter(&value))) {
            snapshot.jitterMs = value;
        }
        if (SUCCEEDED(m_frame->m_pQP->get_AvgSyncOffset(&value))) {
            snapshot.averageSyncOffsetMs = value;
        }
    }
}

void CPlayerControlService::Execute(const PlayerControlRequest& request, PlayerControlResult& result)
{
    result = PlayerControlResult();
    if (!m_frame) {
        Fail(result, -32000, "Player control service is not attached");
        return;
    }

    switch (request.method) {
        case PlayerControlMethod::GET_STATE:
            FillState(result.snapshot);
            result.success = true;
            break;

        case PlayerControlMethod::GET_DIAGNOSTICS:
            FillState(result.snapshot);
            FillDiagnostics(result.snapshot);
            result.success = true;
            break;

        case PlayerControlMethod::PLAY:
            m_frame->OnApiPlay();
            result.success = true;
            break;

        case PlayerControlMethod::PAUSE:
            m_frame->OnApiPause();
            result.success = true;
            break;

        case PlayerControlMethod::STOP:
            m_frame->OnPlayStop();
            result.success = true;
            break;

        case PlayerControlMethod::QUIT:
            result.success = true;
            m_frame->PostMessage(WM_CLOSE);
            break;

        case PlayerControlMethod::SEEK:
            if (m_frame->GetLoadState() != MLS::LOADED) {
                Fail(result, -32010, "No media is loaded");
            } else if (request.numberValue < 0.0 || request.numberValue > 3155760000.0) {
                Fail(result, -32602, "Position must be between 0 and 100 years");
            } else {
                REFERENCE_TIME target = static_cast<REFERENCE_TIME>(request.numberValue * 10000000.0);
                const REFERENCE_TIME duration = m_frame->GetDur();
                if (duration > 0 && target > duration) {
                    target = duration;
                }
                m_frame->SeekTo(target, false);
                result.success = true;
            }
            break;

        case PlayerControlMethod::SET_RATE:
            if (m_frame->GetLoadState() != MLS::LOADED) {
                Fail(result, -32010, "No media is loaded");
            } else if (request.numberValue < 0.05 || request.numberValue > 16.0) {
                Fail(result, -32602, "Rate must be between 0.05 and 16.0");
            } else {
                m_frame->SetPlayingRate(request.numberValue);
                result.success = true;
            }
            break;

        case PlayerControlMethod::SET_VOLUME:
            if (request.integerValue < 0 || request.integerValue > 100) {
                Fail(result, -32602, "Volume must be between 0 and 100");
            } else {
                m_frame->m_wndToolBar.SetVolume(request.integerValue);
                result.success = true;
            }
            break;

        case PlayerControlMethod::SET_MUTE:
            if (m_frame->IsMuted() != (request.integerValue != 0)) {
                m_frame->m_wndToolBar.SetMute(request.integerValue != 0);
                m_frame->OnPlayVolume(ID_VOLUME_MUTE);
            }
            result.success = true;
            break;

        case PlayerControlMethod::SET_AUDIO_TRACK:
            if (m_frame->GetLoadState() != MLS::LOADED || request.integerValue < 0) {
                Fail(result, -32602, "A loaded media item and a non-negative audio track index are required");
            } else {
                m_frame->SetAudioTrackIdx(request.integerValue);
                if (m_frame->GetCurrentAudioTrackIdx() == request.integerValue) {
                    result.success = true;
                } else {
                    Fail(result, -32602, "Audio track index is not available");
                }
            }
            break;

        case PlayerControlMethod::SET_SUBTITLE_TRACK:
            if (m_frame->GetLoadState() != MLS::LOADED || request.integerValue < -1) {
                Fail(result, -32602, "A loaded media item and subtitle index -1 or greater are required");
            } else {
                m_frame->SetSubtitleTrackIdx(request.integerValue);
                if (m_frame->GetCurrentSubtitleTrackIdx() == request.integerValue) {
                    result.success = true;
                } else {
                    Fail(result, -32602, "Subtitle track index is not available");
                }
            }
            break;

        case PlayerControlMethod::OPEN_MEDIA: {
            CString path(request.textValue);
            if (m_frame->GetMediaState() == State_Running) {
                m_frame->MediaControlPause(true);
            }
            if (m_frame->CanSendToYoutubeDL(path)) {
                if (m_frame->ProcessYoutubeDLURL(path, false)) {
                    m_frame->PostMessage(WM_MPC_OPENCURPLAYLIST, 0, 0);
                    result.success = true;
                    break;
                }
                if (m_frame->IsOnYDLWhitelist(path)) {
                    Fail(result, -32020, "yt-dlp could not resolve the URL");
                    break;
                }
            }
            CAtlList<CString> files;
            files.AddHead(path);
            m_frame->m_wndPlaylistBar.Open(files, false);
            m_frame->PostMessage(WM_MPC_OPENCURPLAYLIST, 0, 0);
            result.success = true;
            break;
        }
    }
}
