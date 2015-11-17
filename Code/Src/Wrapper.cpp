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
  cl_uint  uiLLNode, uiDBit;
  
  tReq.uiType = HTS_REQ_TYPE_ADD; 
  tReq.uiKey  = 12;

  if(tFrontEnd.uiSubmitReq(tFid, tReq, tReqEvent) == HTS_OK)
  {
    cl_uint   uiStatus;
    cl_uint   uiReqStatus;

    //std::cout << "waiting on:" << std::endl;
    //std::cout << (long)(tFid) << ":";
    //std::cout << tReqEvent << ":";
    //std::cout << ((tFid->pThreadRequest[tReqEvent]).uiFlags) << std::endl;
    
    uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&uiStatus);
    while (uiReqStatus == HTS_NOT_OK)
  	{
  	  uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&uiStatus);
  	}

    if(uiReqStatus == HTS_REQ_COMPLETED)
      {
	uiLLNode = GET_PTR(uiStatus);
	uiDBit   = GET_DBIT(uiStatus);
	if (uiDBit)
	  {
	    std::cout << "ADD allocated node at: " << uiLLNode << std::endl;
	  }
      }
  }

  tReq.uiType   = HTS_REQ_TYPE_REMOVE; 
  tReq.uiKey    = 14;
  tReq.uiStatus = uiLLNode;
  
  if(tFrontEnd.uiSubmitReq(tFid, tReq, tReqEvent) == HTS_OK)
  {
    cl_uint   uiStatus;
    cl_uint   uiReqStatus;

    uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&uiStatus);
    while (uiReqStatus == HTS_NOT_OK)
  	{
  	  uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&uiStatus);
  	}

    if(uiReqStatus == HTS_REQ_COMPLETED)
      {
	uiLLNode = GET_PTR(uiStatus);
	uiDBit   = GET_DBIT(uiStatus);
	if(uiDBit)
	  {
	    std::cout << "REMOVE freed node at: " << uiLLNode << std::endl;
	  }
      }
  }

  tReq.uiType = HTS_REQ_TYPE_ADD; 
  tReq.uiKey  = 14;

  if(tFrontEnd.uiSubmitReq(tFid, tReq, tReqEvent) == HTS_OK)
  {
    cl_uint   uiStatus;
    cl_uint   uiReqStatus;

    uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&uiStatus);
    while (uiReqStatus == HTS_NOT_OK)
  	{
  	  uiReqStatus = tFrontEnd.uiGetStatus(tFid,tReqEvent,&uiStatus);
  	}

    if(uiReqStatus == HTS_REQ_COMPLETED)
      {
	uiLLNode = GET_PTR(uiStatus);
	uiDBit   = GET_DBIT(uiStatus);
	if(uiDBit)
	  {
	    std::cout << "ADD allocated node at: " << uiLLNode << std::endl;
	  }
      }
  }
  
  tFrontEnd.uiDeRegister(tFid);

  //std::cout << "waiting for front end thread to finish." << std::endl;
  tFrontEnd.uiCloseFrontEnd();
  tFrontEnd.uiReleaseOCLKernels();

  uiReleaseOCLContext(&tOclContext);
  return 0;
}
