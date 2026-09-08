/*
 * (C) 2008-2014 see Authors.txt
 *
 * This file is part of MPC-HC.
 *
 * MPC-HC is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * MPC-HC is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "stdafx.h"
#include "Ifo.h"


#ifdef WORDS_BIGENDIAN
#define bswap_16(x) (x)
#define bswap_32(x) (x)
#define bswap_64(x) (x)
#else

// code from bits/byteswap.h (C) 1997, 1998 Free Software Foundation, Inc.
#define bswap_16(x) \
    ((((x) >> 8) & 0xff) | (((x) & 0xff) << 8))

// code from bits/byteswap.h (C) 1997, 1998 Free Software Foundation, Inc.
#define bswap_32(x)                                            \
    ((((x) & 0xff000000) >> 24) | (((x) & 0x00ff0000) >>  8) | \
    (((x)  & 0x0000ff00) <<  8) | (((x) & 0x000000ff) << 24))

#define bswap_64(x)                                       \
    (__extension__                                        \
    ({ union { __extension__ unsigned long long int __ll; \
                unsigned long int __l[2]; } __w, __r;     \
        __w.__ll = (x);                                   \
        __r.__l[0] = bswap_32 (__w.__l[1]);               \
        __r.__l[1] = bswap_32 (__w.__l[0]);               \
        __r.__ll; }))
#endif

#ifdef WORDS_BIGENDIAN
#define be2me_16(x) (x)
#define be2me_32(x) (x)
#define be2me_64(x) (x)
#define le2me_16(x) bswap_16(x)
#define le2me_32(x) bswap_32(x)
#define le2me_64(x) bswap_64(x)
#else
#define be2me_16(x) bswap_16(x)
#define be2me_32(x) bswap_32(x)
#define be2me_64(x) bswap_64(x)
#define le2me_16(x) (x)
#define le2me_32(x) (x)
#define le2me_64(x) (x)
#endif

#define DVD_VIDEO_LB_LEN    2048
#define IFO_HDR_LEN            8
#define LU_SUB_LEN             8

extern HANDLE(__stdcall* Real_CreateFileW)(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);


uint32_t get4bytes(const BYTE* buf)
{
    return be2me_32(*((uint32_t*)buf));
}


// VMG files
#define OFF_VMGM_PGCI_UT(buf)   get4bytes (buf + 0xC8)

// VTS files
#define OFF_VTSM_PGCI_UT(buf)   get4bytes (buf + 0xD0)
#define OFF_VTS_PGCIT(buf)      get4bytes (buf + 0xCC)


CIfo::CIfo()
    : m_pBuffer(nullptr)
    , m_dwSize(0)
    , m_pPGCI(nullptr)
    , m_pPGCIT(nullptr)
{
}

CIfo::~CIfo()
{
    delete [] m_pBuffer;
}

bool CIfo::IsRangeInBuffer(const void* ptr, size_t length) const
{
    if (!m_pBuffer || !ptr) {
        return false;
    }

    const uintptr_t begin = reinterpret_cast<uintptr_t>(m_pBuffer);
    const uintptr_t address = reinterpret_cast<uintptr_t>(ptr);
    if (address < begin) {
        return false;
    }

    const uintptr_t offset = address - begin;
    return offset <= m_dwSize && length <= static_cast<size_t>(m_dwSize - offset);
}

bool CIfo::IsTableInBuffer(const ifo_hdr_t* hdr) const
{
    if (!IsRangeInBuffer(hdr, sizeof(*hdr))) {
        return false;
    }

    const size_t offset = reinterpret_cast<const BYTE*>(hdr) - m_pBuffer;
    const uint32_t tableLength = be2me_32(hdr->len);
    return tableLength >= IFO_HDR_LEN && tableLength <= m_dwSize - offset;
}

int CIfo::GetMiscPGCI(ifo_hdr_t* hdr, int title, uint8_t** ptr)
{
    if (!ptr) {
        return -1;
    }

    pgc_t* pgc = GetPGCI(title, hdr);
    if (!pgc) {
        return -1;
    }

    *ptr = reinterpret_cast<uint8_t*>(pgc);
    return 0;
}

void CIfo::RemovePgciUOPs(uint8_t* ptr)
{
    auto* hdr = reinterpret_cast<ifo_hdr_t*>(ptr);
    if (!IsTableInBuffer(hdr)) {
        return;
    }

    const uint16_t num = be2me_16(hdr->num);
    for (uint16_t i = 0; i < num; ++i) {
        uint8_t* pgcPtr = nullptr;
        if (GetMiscPGCI(hdr, i, &pgcPtr) >= 0) {
            auto* pgc = reinterpret_cast<pgc_t*>(pgcPtr);
            constexpr size_t prohibitedOpsEnd = offsetof(pgc_t, prohibited_ops) + sizeof(uint32_t);
            if (IsRangeInBuffer(pgc, prohibitedOpsEnd)) {
                pgc->prohibited_ops = 0;
            }
        }
    }
}

CIfo::pgc_t* CIfo::GetFirstPGC()
{
    if (!m_pBuffer) {
        return nullptr;
    }

    auto* pgc = reinterpret_cast<pgc_t*>(m_pBuffer + 0x0400);
    constexpr size_t prohibitedOpsEnd = offsetof(pgc_t, prohibited_ops) + sizeof(uint32_t);
    return IsRangeInBuffer(pgc, prohibitedOpsEnd) ? pgc : nullptr;
}

CIfo::pgc_t* CIfo::GetPGCI(const int title, const ifo_hdr_t* hdr)
{
    if (title < 0 || !IsTableInBuffer(hdr)) {
        return nullptr;
    }

    const uint16_t count = be2me_16(hdr->num);
    if (title >= count) {
        return nullptr;
    }

    const size_t tableLength = be2me_32(hdr->len);
    const size_t entryOffset = IFO_HDR_LEN + static_cast<size_t>(title) * sizeof(pgci_sub_t);
    if (entryOffset > tableLength || sizeof(pgci_sub_t) > tableLength - entryOffset) {
        return nullptr;
    }

    const BYTE* table = reinterpret_cast<const BYTE*>(hdr);
    const auto* pgciSub = reinterpret_cast<const pgci_sub_t*>(table + entryOffset);
    const size_t startOffset = be2me_32(pgciSub->start);
    if (startOffset >= tableLength || sizeof(ifo_hdr_t) > tableLength - startOffset) {
        return nullptr;
    }

    auto* result = const_cast<BYTE*>(table) + startOffset;
    return IsRangeInBuffer(result, sizeof(ifo_hdr_t)) ? reinterpret_cast<pgc_t*>(result) : nullptr;
}

bool CIfo::IsVTS()
{
    if (m_dwSize < 12 || (strncmp((char*)m_pBuffer, "DVDVIDEO-VTS", 12) != 0)) {
        return false;
    }

    return true;
}

bool CIfo::IsVMG()
{
    if (m_dwSize < 12 || (strncmp((char*)m_pBuffer, "DVDVIDEO-VMG", 12) != 0)) {
        return false;
    }

    return true;
}

bool CIfo::OpenFile(LPCTSTR strFile)
{
    delete [] m_pBuffer;
    m_pBuffer = nullptr;
    m_dwSize = 0;
    m_pPGCI = nullptr;
    m_pPGCIT = nullptr;

    bool bRet = false;
    HANDLE hFile = Real_CreateFileW(strFile, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFile != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER size = {};
        // Min size comes from the DVD sector size. The parser deliberately caps
        // IFO input at 8 MiB and requires whole sectors.
        if (GetFileSizeEx(hFile, &size) && size.QuadPart >= DVD_VIDEO_LB_LEN
                && size.QuadPart <= 0x800000 && !(size.QuadPart % DVD_VIDEO_LB_LEN)) {
            const DWORD expectedSize = static_cast<DWORD>(size.QuadPart);
            m_pBuffer = DEBUG_NEW BYTE[expectedSize];

            DWORD totalRead = 0;
            while (totalRead < expectedSize) {
                DWORD bytesRead = 0;
                if (!ReadFile(hFile, m_pBuffer + totalRead, expectedSize - totalRead, &bytesRead, nullptr) || bytesRead == 0) {
                    break;
                }
                totalRead += bytesRead;
            }

            if (totalRead == expectedSize) {
                m_dwSize = totalRead;
                const uint32_t sectorCount = expectedSize / DVD_VIDEO_LB_LEN;
                uint32_t sector = 0;

                if (IsVTS()) {
                    sector = OFF_VTSM_PGCI_UT(m_pBuffer);
                    if (sector && sector < sectorCount) {
                        auto* candidate = reinterpret_cast<ifo_hdr_t*>(m_pBuffer + sector * DVD_VIDEO_LB_LEN);
                        if (IsTableInBuffer(candidate)) {
                            m_pPGCI = candidate;
                        }
                    }
                    if (!m_pPGCI) {
                        TRACE(_T("IFO: Missing or invalid VTSM_PGCI_UT sector\n"));
                    }

                    sector = OFF_VTS_PGCIT(m_pBuffer);
                    if (sector && sector < sectorCount) {
                        auto* candidate = reinterpret_cast<ifo_hdr_t*>(m_pBuffer + sector * DVD_VIDEO_LB_LEN);
                        if (IsTableInBuffer(candidate)) {
                            m_pPGCIT = candidate;
                        }
                    }
                    if (!m_pPGCIT) {
                        TRACE(_T("IFO: Missing or invalid VTS_PGCI sector\n"));
                    }
                } else if (IsVMG()) {
                    sector = OFF_VMGM_PGCI_UT(m_pBuffer);
                    if (sector && sector < sectorCount) {
                        auto* candidate = reinterpret_cast<ifo_hdr_t*>(m_pBuffer + sector * DVD_VIDEO_LB_LEN);
                        if (IsTableInBuffer(candidate)) {
                            m_pPGCI = candidate;
                        }
                    }
                    if (!m_pPGCI) {
                        TRACE(_T("IFO: Missing or invalid VMGM_PGCI_UT sector\n"));
                    }
                }

                bRet = m_pPGCI != nullptr;
            }
        }
        CloseHandle(hFile);
    } else {
        ASSERT(FALSE);
    }

    if (!bRet) {
        delete [] m_pBuffer;
        m_pBuffer = nullptr;
        m_dwSize = 0;
        m_pPGCI = nullptr;
        m_pPGCIT = nullptr;
    }
    return bRet;
}

bool CIfo::RemoveUOPs()
{
    pgc_t* pgc;

    if (m_pPGCI) {
        pgc = GetFirstPGC();
        if (!pgc) {
            return false;
        }
        pgc->prohibited_ops = 0;

        for (int i = 0; i < be2me_16(m_pPGCI->num); i++) {
            pgc = GetPGCI(i, m_pPGCI);
            if (pgc) {
                RemovePgciUOPs((uint8_t*)pgc);
            }
        }
    }
    if (m_pPGCIT) {
        for (int i = 0; i < be2me_16(m_pPGCIT->num); i++) {
            pgc = GetPGCI(i, m_pPGCIT);
            if (pgc) {
                pgc->prohibited_ops = 0;
            }
        }
    }
    return true;
}

bool CIfo::SaveFile(LPCTSTR strFile)
{
    bool bRet = false;

    if (m_pBuffer && m_dwSize > 0) {
        HANDLE hFile = Real_CreateFileW(strFile, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                        nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hFile != INVALID_HANDLE_VALUE) {
            DWORD totalWritten = 0;
            while (totalWritten < m_dwSize) {
                DWORD written = 0;
                if (!WriteFile(hFile, m_pBuffer + totalWritten, m_dwSize - totalWritten, &written, nullptr) || written == 0) {
                    break;
                }
                totalWritten += written;
            }
            bRet = totalWritten == m_dwSize;
            CloseHandle(hFile);
            if (!bRet) {
                DeleteFile(strFile);
            }
        }
    }

    ASSERT(bRet);
    return bRet;
}
