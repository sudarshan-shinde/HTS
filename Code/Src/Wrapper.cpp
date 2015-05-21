#include <iostream>
#include <fstream>
#include "HTSOcl.hpp"
#include "HTSFrontEnd.hpp"

//const char* pProgramFile = "HTSKernels.cl";

int main()
{
  //get OCL context
  TOclContext tOclContext;

  if (uiGetOCLContext(&tOclContext) != HTS_OK)
    {
      std::cout << "failed to initialize OCL context" << std::endl;
      return -1;
    }

  //get the front end 
  CFrontEnd tFrontEnd;

  //bind context
  if(tFrontEnd.uiBindOCLContext(&tOclContext) != HTS_OK)
    {
      std::cout << "failed to bind OCL context." << std::endl;
      return -1;
    }

  //build OCL kernels
  if(tFrontEnd.uiBuildOCLKernels() != HTS_OK)
    {
      std::cout << "failed to build OCL kernels." << std::endl;
      return -1;
    }

  //start front end processing
  tFrontEnd.uiOpenFrontEnd();

  //register the thread 
  TFid  tFid = tFrontEnd.tRegister();
  
  cl_uint uiNoThreads = tFrontEnd.uiGetThreadCount();

  //std::cout << "Threads:" << uiNoThreads << std::endl;

  //submit some requests
  CRequest tReq;
  TEvent   tReqEvent;

  tReq.uiKey = 12;

  if(tFrontEnd.uiSubmitReq(tFid, tReq, tReqEvent) == HTS_OK)
    {
      void*   pStatus;
      cl_uint uiReqStatus;

      /*
      std::cout << "waiting on:" << std::endl;
      std::cout << (long)(tFid) << ":";
      std::cout << tReqEvent << ":";
      std::cout << ((tFid->pThreadRequest[tReqEvent]).uiFlags) << std::endl;
      */
      
      uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&pStatus);
      while (uiReqStatus == HTS_NOT_OK)
	{
	  uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&pStatus);
	}

      if(uiReqStatus == HTS_REQ_COMPLETED)
	std::cout << "request is successful." << std::endl;
    }

  tFrontEnd.uiDeRegister(tFid);

  //std::cout << "waiting for front end thread to finish." << std::endl;
  tFrontEnd.uiCloseFrontEnd();
  tFrontEnd.uiReleaseOCLKernels();

  uiReleaseOCLContext(&tOclContext);
  return 0;
}
