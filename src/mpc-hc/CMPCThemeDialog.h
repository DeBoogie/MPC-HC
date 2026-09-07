#pragma once
#include <afxwin.h>
#include "CMPCThemeButton.h"
#include "CMPCThemeGroupBox.h"
#include "CMPCThemeLinkCtrl.h"
#include "CMPCThemeUtil.h"

class CMPCThemeDialog :
    public CDialog, public CMPCThemeUtil
{
public:
    CMPCThemeDialog(bool isDummy = false);
    explicit CMPCThemeDialog(UINT nIDTemplate, CWnd* pParentWnd = NULL);
    virtual ~CMPCThemeDialog();
    void fulfillThemeReqs() { CMPCThemeUtil::fulfillThemeReqs((CWnd*)this); };
    BOOL OnInitDialog();
    void SetSpecialCase(CMPCThemeUtil::SpecialThemeCases specialCase) { this->specialCase = specialCase; }
    DECLARE_DYNAMIC(CMPCThemeDialog)
    DECLARE_MESSAGE_MAP()
    afx_msg HBRUSH OnCtlColor(CDC* pDC, CWnd* pWnd, UINT nCtlColor);
    BOOL PreTranslateMessage(MSG* pMsg);
private:
    bool isDummy = false;
    CMPCThemeUtil::SpecialThemeCases specialCase = NoSpecialCase;
public:
    afx_msg void OnHScroll(UINT nSBCode, UINT nPos, CScrollBar* pScrollBar);
};

