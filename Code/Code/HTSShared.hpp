
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
  cl_uint         uiStatus;
  cl_uint	  uiNode;
} TQueuedRequest;

typedef struct sLLNode
{
  cl_uint        pE[OCL_WG_SIZE];
  cl_uint        uiNext; 
} TLLNode;

typedef struct sMiscData
{
  cl_uint	 uiHeadIndex ; // Addded --> Nipuna
} TMiscData;

#else
#include "HTSConsts.hpp"

typedef struct SQueuedRequest
{
  void*           pFid;
  uint            uiReqId;
  uint            uiType;
  uint            uiKey;
  uint            uiFlags;
  uint            uiStatus;
  uint		  uiNode ;
} TQueuedRequest;

typedef struct sLLNode
{
  uint           pE[OCL_WG_SIZE];
  uint           uiNext; 
} TLLNode;

typedef struct sMiscData
{
  uint		 uiHeadIndex; 
} TMiscData;

#endif

#endif
