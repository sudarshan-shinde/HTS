
#ifndef _HTS_BASICS_HPP_
#define _HTS_BASICS_HPP_

#include <windows.h>
#include <CL/opencl.h>
#include "HTSConsts.hpp"

class CRequest
{
public:
  cl_uint   uiKey;
  cl_uint   uiFlags;
  void*     pStatus;

  CRequest()
  {
    uiKey   = uiFlags = 0;
    pStatus = NULL;
  };
};

class CFidS
{
public:
  cl_uint          uiReqCount;
  CRequest         pThreadRequest[THREAD_REQUEST_BUFFER_SIZE];

  CFidS()
  {
    uiReqCount = 0;
  };
};

typedef CFidS*   TFid;
typedef UINT     TEvent;

#endif
