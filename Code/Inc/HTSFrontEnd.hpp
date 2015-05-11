
#pragma once

#include <iostream>
#include <windows.h>
#include "HTSConsts.hpp"
#include "HTSBasics.hpp"
#include "HTSReqQueue.hpp"
#include "HTSOcl.hpp"

class CFrontEnd
{
public:
  //constructor and destructor
  CFrontEnd();
  ~CFrontEnd();

  //OCL functions
  UINT          uiBindOCLContext(TOclContext* pOclContextIn);
  UINT          uiBuildOCLKernels();
  UINT          uiReleaseOCLKernels();

  //interface functions
  TFid          tRegister();
  UINT          uiDeRegister(TFid tFid);
  UINT          uiSubmitReq(TFid tFid, CRequest& cReq, TEvent& tEvent);
  UINT          uiGetStatus(TFid tFid, TEvent& tEvent, void** ppStatus);

  //query functions
  UINT          uiGetThreadCount();

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

  //ocl program and kernel
  cl_program       oclProgram;
  cl_kernel        oclKernel;
  
  //filename of the OCL code
  const char*      pProgramFile = "HTSKernels.cl";
};
