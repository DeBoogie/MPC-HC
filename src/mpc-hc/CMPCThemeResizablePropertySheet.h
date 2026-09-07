#pragma once
#include "CMPCThemeUtil.h"
#include "ResizableLib/ResizableSheet.h"

class CMPCThemeResizablePropertySheet : public CResizableSheet, public CMPCThemeUtil
{
public:
    DECLARE_DYNAMIC(CMPCThemeResizablePropertySheet)
    CMPCThemeResizablePropertySheet(UINT nIDCaption, CWnd* pParentWnd = nullptr, UINT iSelectPage = 0);
    CMPCThemeResizablePropertySheet(LPCTSTR pszCaption, CWnd* pParentWnd = nullptr, UINT iSelectPage = 0);
    virtual ~CMPCThemeResizablePropertySheet();

    virtual BOOL OnInitDialog();
    void fulfillThemeReqs();
    virtual INT_PTR DoModal(); //override to handle RTL without using SetWindowLongPtr

    bool isModal;
    DECLARE_MESSAGE_MAP()
public:
    afx_msg HBRUSH OnCtlColor(CDC* pDC, CWnd* pWnd, UINT nCtlColor);
};

