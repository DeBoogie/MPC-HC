#pragma once
#include "CMPCThemeUtil.h"
#include "ResizableLib/ResizablePage.h"
class CMPCThemeResizablePropertyPage : public CResizablePage, public CMPCThemeUtil
{
public:
    CMPCThemeResizablePropertyPage() {}; //for dynamic creation
    CMPCThemeResizablePropertyPage(UINT nIDTemplate, UINT nIDCaption);
    virtual ~CMPCThemeResizablePropertyPage();


    void fulfillThemeReqs() { CMPCThemeUtil::fulfillThemeReqs((CWnd*)this); };
    DECLARE_DYNCREATE(CMPCThemeResizablePropertyPage)

    DECLARE_MESSAGE_MAP()
    afx_msg HBRUSH OnCtlColor(CDC* pDC, CWnd* pWnd, UINT nCtlColor);
protected:
    virtual BOOL OnInitDialog();

};

