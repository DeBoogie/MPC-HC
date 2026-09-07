#include "stdafx.h"
#include "CMPCThemeResizablePropertySheet.h"
#include "CMPCTheme.h"
#include "mplayerc.h"

CMPCThemeResizablePropertySheet::CMPCThemeResizablePropertySheet(UINT nIDCaption, CWnd* pParentWnd, UINT iSelectPage)
    :CResizableSheet(nIDCaption, pParentWnd, iSelectPage)
    ,isModal(false)
{
}

CMPCThemeResizablePropertySheet::CMPCThemeResizablePropertySheet(LPCTSTR pszCaption, CWnd* pParentWnd, UINT iSelectPage)
    :CResizableSheet(pszCaption, pParentWnd, iSelectPage)
    ,isModal(false)
{
}

CMPCThemeResizablePropertySheet::~CMPCThemeResizablePropertySheet()
{
}

IMPLEMENT_DYNAMIC(CMPCThemeResizablePropertySheet, CResizableSheet)
BEGIN_MESSAGE_MAP(CMPCThemeResizablePropertySheet, CResizableSheet)
    ON_WM_CTLCOLOR()
END_MESSAGE_MAP()

BOOL CMPCThemeResizablePropertySheet::OnInitDialog()
{
    BOOL bResult = __super::OnInitDialog();
    fulfillThemeReqs();
    return bResult;
}

void CMPCThemeResizablePropertySheet::fulfillThemeReqs()
{
    CMPCThemeUtil::enableWindows10DarkFrame(this);
    if (AppIsThemeLoaded()) {
        SetSizeGripBkMode(TRANSPARENT); //fix for gripper in mpc theme
    }
    CMPCThemeUtil::fulfillThemeReqs((CWnd*)this);
}

HBRUSH CMPCThemeResizablePropertySheet::OnCtlColor(CDC* pDC, CWnd* pWnd, UINT nCtlColor)
{
    if (AppNeedsThemedControls()) {
        LRESULT lResult;
        if (pWnd->SendChildNotifyLastMsg(&lResult)) {
            return (HBRUSH)lResult;
        }
        pDC->SetTextColor(CMPCTheme::TextFGColor);
        pDC->SetBkColor(CMPCTheme::ControlAreaBGColor);
        return controlAreaBrush;
    } else {
        HBRUSH hbr = __super::OnCtlColor(pDC, pWnd, nCtlColor);
        return hbr;
    }
}

INT_PTR CMPCThemeResizablePropertySheet::DoModal() {
    isModal = true;
    PreDoModalRTL(&m_psh);
    return __super::DoModal();
}
