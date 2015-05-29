
#ifndef _HTS_SHARED_HPP_
#define _HTS_SHARED_HPP_

#ifndef _OCL_CODE_

#include <windows.h>
#include "HTSBasics.hpp"

typedef struct SQueuedRequest
{
  TFid            tFid;
  cl_uint         uiReqId;
  cl_uint         uiType; 
  cl_uint         uiKey;
  cl_uint         uiFlags;
  void*           pStatus;
} TQueuedRequest;

typedef struct sLLNode
{
  cl_uint        pE[OCL_WG_SIZE];
  cl_uint        uiNext; 
} TLLNode;
  
#else
#include "HTSConsts.hpp"

typedef struct SQueuedRequest
{
  void*           pFid;
  uint            uiReqId;
  uint            uiType;
  uint            uiKey;
  uint            uiFlags;
  void*           pStatus;
} TQueuedRequest;

typedef struct sLLNode
{
  uint           pE[OCL_WG_SIZE];
  uint           uiNext; 
} TLLNode;

#endif

#endif
