
#pragma once

#include <iostream>
#include <windows.h>
#include "HTSConsts.hpp"
#include "HTSBasics.hpp"
#include "HTSReqQueue.hpp"
#include "HTSOcl.hpp"

#define FILENAME "HTSKernels.cl"

class CFrontEnd
{
public:
  //constructor and destructor
  CFrontEnd();
  ~CFrontEnd();

  UINT CFrontEnd::uiOpenFrontEnd();
  UINT CFrontEnd::uiCloseFrontEnd();

  //OCL functions
  UINT          uiBindOCLContext(TOclContext* pOclContextIn);
  UINT          uiBuildOCLKernels();
  UINT          uiReleaseOCLKernels();

  //interface functions
  TFid          tRegister();
  UINT          uiDeRegister(TFid tFid);
  UINT          uiSubmitReq(TFid tFid, CRequest& cReq, TEvent& tEvent);
  UINT          uiGetStatus(TFid tFid, TEvent tEvent, cl_uint& uiStatus);

  //query functions
  UINT          uiGetThreadCount();
  UINT          uiInspectElements();
  
  //top level thread function
  DWORD         dwCFrontThread();

private:
  UINT             uiTidCount;
  UINT             uiReqCount; 
  CRequestQueue    tReqQueue;
  HANDLE           tThreadHandle;
  DWORD            dwThreadId;
  HANDLE           tCloseThreadEvent; 
  TOclContext*     pOclContext;

  //svm buffer for shared request queue
  TQueuedRequest*  pOclReqQueue; 
  TLLNode*         pNodePool;
  TLLNode*         pHashTable;
  TMiscData*       pMiscData;
  void*            pSVMBuf;

  //ocl program and kernel
  cl_program       oclProgram;
  cl_kernel        oclKernel;
  
  //filename of the OCL code
  char      pProgramFile[256] ;
};
