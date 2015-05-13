
#ifndef _HTS_SHARED_HPP_
#define _HTS_SHARED_HPP_

#ifndef _OCL_CODE_

#include <windows.h>
#include "HTSBasics.hpp"

typedef struct SQueuedRequest
{
  TFid            tFid;
  cl_uint         uiReqId;
  cl_uint         uiKey;
  cl_uint         uiFlags;
  void*           pStatus;
} TQueuedRequest;
  
#else
#include "HTSConsts.hpp"

typedef struct SQueuedRequest
{
  void*           pFid;
  uint            uiReqId;
  uint            uiKey;
  uint            uiFlags;
  void*           pStatus;
} TQueuedRequest;
#endif


#endif
