
#pragma once

#include <CL/cl.h>
#include <windows.h>
#include <iostream>
#include <fstream>
#include "HTSOcl.hpp"
#include "HTSFrontEnd.hpp"
#include "TestConsts.hpp"

typedef unsigned int   uint;
typedef DWORD (WINAPI *TThreadFnPtr)(LPVOID);

class CThrParam
{
public:
  uint       uiId;
  uint       uiReqType;
  uint       uiKeyStart;
  uint       uiKeyEnd;
  uint       uiOrder;
  bool       bVerbose;
  CFrontEnd* pFrontEnd;
};

DWORD WINAPI dwThreadFn(LPVOID pParam);

