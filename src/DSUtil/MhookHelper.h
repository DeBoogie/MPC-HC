/*
 * (C) 2015 see Authors.txt
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

#pragma once

#if defined(_M_ARM64)
#define MPC_ARM64_NO_MINHOOK 1
using MH_STATUS = int;
constexpr MH_STATUS MH_OK = 0;
#define MH_ALL_HOOKS nullptr
inline MH_STATUS MH_Initialize() { return MH_OK; }
inline MH_STATUS MH_EnableHook(LPVOID) { return MH_OK; }
inline MH_STATUS MH_Uninitialize() { return MH_OK; }
#else
#include "minhook/minhook/include/MinHook.h"
#endif

template <typename T>
inline BOOL Mhook_SetHookEx(T** ppSystemFunction, PVOID pHookFunction)
{
#if defined(MPC_ARM64_NO_MINHOOK)
    UNREFERENCED_PARAMETER(ppSystemFunction);
    UNREFERENCED_PARAMETER(pHookFunction);
    return FALSE;
#else
    return MH_CreateHook(*ppSystemFunction, pHookFunction, reinterpret_cast<LPVOID*>(ppSystemFunction)) == MH_OK;
#endif
}
