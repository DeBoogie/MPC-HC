#include "stdafx.h"
#include "CMPCThemeResizablePropertyPage.h"

CMPCThemeResizablePropertyPage::CMPCThemeResizablePropertyPage(UINT nIDTemplate, UINT nIDCaption)
    : CResizablePage(nIDTemplate, nIDCaption)
{

}

CMPCThemeResizablePropertyPage::~CMPCThemeResizablePropertyPage()
{
}

BOOL CMPCThemeResizablePropertyPage::OnInitDialog()
{
    __super::OnInitDialog();
    fulfillThemeReqs();
    return 0;
}

IMPLEMENT_DYNCREATE(CMPCThemeResizablePropertyPage, CResizablePage)
BEGIN_MESSAGE_MAP(CMPCThemeResizablePropertyPage, CResizablePage)
    ON_WM_CTLCOLOR()
END_MESSAGE_MAP()

HBRUSH CMPCThemeResizablePropertyPage::OnCtlColor(CDC* pDC, CWnd* pWnd, UINT nCtlColor)
{
    HBRUSH ret;
    ret = getCtlColor(pDC, pWnd, nCtlColor);
    if (nullptr != ret) {
        return ret;
    } else {
        return __super::OnCtlColor(pDC, pWnd, nCtlColor);
    }
}
