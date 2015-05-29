
#ifndef _HTS_BASICS_HPP_
#define _HTS_BASICS_HPP_

#include <windows.h>
#include <CL/opencl.h>
#include "HTSConsts.hpp"

class CRequest
{
public:
  cl_uint   uiType;
  cl_uint   uiKey;
  cl_uint   uiFlags;
  cl_uint   uiStatus;

  CRequest()
  {
    uiKey    = uiFlags = 0;
    uiStatus = 0;
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

typedef CFidS volatile*   TFid;
typedef UINT              TEvent;

#endif