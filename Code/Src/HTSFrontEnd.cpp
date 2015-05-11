#include "HTSFrontEnd.hpp"

DWORD WINAPI dwCFrontThreadStub(LPVOID pParam);
  
CFrontEnd::CFrontEnd()
{
  //initialize variables
  uiTidCount  = 0;
  uiReqCount  = 0;
  pOclContext = NULL;

  //create a process thread for handling requests
  tThreadHandle = CreateThread(NULL,
			       0,
			       dwCFrontThreadStub,
			       static_cast<LPVOID>(this),
			       0,
			       &dwThreadId);

  tCloseThreadEvent = CreateEvent(NULL,
				  TRUE,
				  FALSE,
				  NULL);
}

CFrontEnd::~CFrontEnd()
{
  //terminate the thread
  SetEvent(tCloseThreadEvent);
  WaitForSingleObject(tThreadHandle,INFINITE);

  //close the event
  CloseHandle(tCloseThreadEvent);

}

UINT CFrontEnd::uiBindOCLContext(TOclContext* pOclContextIn)
{
  pOclContext = pOclContextIn;
  return HTS_OK;
}

UINT CFrontEnd::uiBuildOCLKernels()
{
  //allocate the required memeory
  size_t           uiSVMSize = OCL_REQ_QUEUE_SIZE*sizeof(TQueuedRequest);
  cl_svm_mem_flags tSVMFlags = CL_MEM_READ_WRITE |
                               CL_MEM_SVM_FINE_GRAIN_BUFFER |
                               CL_MEM_SVM_ATOMICS;
  
  pOclReqQueue     = (TQueuedRequest *)clSVMAlloc(pOclContext->oclContext,
						  tSVMFlags,
						  uiSVMSize,
						  0);

  if(pOclReqQueue == NULL)
    {
      return HTS_NOT_OK;
    }
  
  //create the program
  std::string sourceStr;
  cl_uint iStatus     = (cl_int)(uiConvertToString(pProgramFile, sourceStr));
  const char *source  = sourceStr.c_str();
  size_t sourceSize[] = {strlen(source)};
  
  oclProgram = clCreateProgramWithSource(pOclContext->oclContext,
					 1,
					 &source,
					 sourceSize,
					 NULL);

  iStatus = clBuildProgram(oclProgram,
			   1,
			   pOclContext->pOclDevices,
			   NULL,
			   NULL,
			   NULL);
				 
  /* create kernels */
  oclKernel = clCreateKernel(oclProgram,
			     "HTSTopKernel",
			     NULL);  
  
  return HTS_OK;
}

UINT CFrontEnd::uiReleaseOCLKernels()
{
  if(pOclReqQueue)
    clSVMFree(pOclContext->oclContext, pOclReqQueue);
  
  clReleaseKernel(oclKernel);
  clReleaseProgram(oclProgram);
}

TFid CFrontEnd::tRegister()
{
  //increment the thread counter
  LONG* pThreadCount = (LONG*)(&uiTidCount);
  InterlockedIncrement(pThreadCount);

  //create structure to hold internal state of the thread
  TFid tFid = new CFidS;

  return tFid;
}

cl_uint CFrontEnd::uiDeRegister(TFid tFid)
{
  //delete threads internal state structure
  if(!tFid)
    return HTS_NOT_OK;

  delete tFid;

  //decrement the thread count
  LONG* pThreadCount = (LONG*)(&uiTidCount);
  InterlockedDecrement(pThreadCount);

  return HTS_OK;
}

cl_uint CFrontEnd::uiSubmitReq(TFid tFid, CRequest& cReq, TEvent& tEvent)
{
  //check if a slot is available for the request
  if(tFid->uiReqCount >= THREAD_REQUEST_BUFFER_SIZE)
    return HTS_NOT_OK;
  
  /* DEBUG 
  std::cout << "searching req id..." << std::endl;
   DEBUG */

  bool    bFoundFlag   = false;
  cl_uint uiReqId      = 0;
  while(!bFoundFlag)
    {
      cl_uint& uiFlags = (tFid->pThreadRequest[uiReqId]).uiFlags;
      if(uiFlags & HTS_REQ_FULL)
	{
	  uiReqId++;
	}
      else
	{
	  bFoundFlag = true;
	}
    }

  //put the request in private list
  tFid->pThreadRequest[uiReqId] = cReq;
  (tFid->pThreadRequest[uiReqId]).uiFlags |= HTS_REQ_FULL; 
  tFid->uiReqCount++;

  //if a request slot is found, put request in the queue
  TQueuedRequest cQReq;
  cQReq.tFid    = tFid;
  cQReq.uiReqId = uiReqId;
  cQReq.uiKey   = cReq.uiKey;
  cQReq.uiFlags = 0;
  cQReq.pStatus = NULL;

  if(tReqQueue.uiPut(&cQReq) != HTS_OK)
    {
      (tFid->pThreadRequest[uiReqId]).uiFlags = 0; 
      tFid->uiReqCount--;

      return HTS_NOT_OK;
    }

  (tFid->pThreadRequest[uiReqId]).uiFlags |= HTS_REQ_QUEUED; 
  tEvent                                   = uiReqId;

  /* DEBUG 
  std::cout << "req id:" << uiReqId << std::endl;
   DEBUG */

  //if it is a blocking request, spin-wait till it is serviced.
  if(cReq.uiFlags & HTS_REQ_BLOCKING)
    {
      cl_uint  uiReqCount = tFid->uiReqCount;
      while(uiReqCount)
	{
	  uiReqCount = tFid->uiReqCount;
	}
    }

  return HTS_OK;
}

cl_uint CFrontEnd::uiGetStatus(TFid tFid, TEvent& tEvent, void** ppStatus)
{
  cl_uint  uiReqId   = (cl_uint)tEvent;
  cl_uint& uiFlags  = (tFid->pThreadRequest[uiReqId]).uiFlags;
  void*    pRStatus = (tFid->pThreadRequest[uiReqId]).pStatus;

  *ppStatus = NULL;
  if(uiFlags & HTS_REQ_COMPLETED)
    {
      uiFlags    = 0;
      *ppStatus  = pRStatus;
      return HTS_REQ_COMPLETED;
    }

  if(uiFlags & HTS_REQ_ABORTED)
    {
      uiFlags    = 0;
      *ppStatus  = pRStatus;
      return HTS_REQ_ABORTED;
    }

  return HTS_NOT_OK;
}

cl_uint CFrontEnd::uiGetThreadCount()
{
  return uiTidCount;
}

DWORD CFrontEnd::dwCFrontThread()
{
  cl_event tEvent;
  size_t   pLocalSize[1]  = {OCL_WG_SIZE};
  size_t   pGlobalSize[1] = {OCL_WG_SIZE};
  
  DWORD    dwWaitStatus   = WaitForSingleObject(tCloseThreadEvent,0);

  UINT  uiReqCount = 0;
  while(dwWaitStatus == WAIT_TIMEOUT)
    {
      //service the queued requests
      TQueuedRequest cQReq;
      BOOL           bSubmitFlag = FALSE;
      
      while(bSubmitFlag == FALSE)
	{
	  if(uiReqCount < OCL_REQ_QUEUE_SIZE)
	    {
	      if(tReqQueue.uiGet(&cQReq) == HTS_OK)
		{
		  pOclReqQueue[uiReqCount++] = cQReq;
		  

		}
	      else
		{
		  bSubmitFlag = TRUE;
		}
	    }
	  else
	    {
	      bSubmitFlag = TRUE;
	    }
	}

      //submit all requests to GPU
      pGlobalSize[0] = (size_t)(uiReqCount);
      pLocalSize[0]  = OCL_WG_SIZE;
      
      clSetKernelArgSVMPointer(oclKernel,
			       0,
			       (void *)(&pOclReqQueue));
      clSetKernelArg(oclKernel,
		     1,
		     sizeof(cl_uint),
		     (void *)(&uiReqCount));

      clEnqueueNDRangeKernel(oclContext->oclCommandQueue,
			     oclKernel,
			     1,
			     NULL,
			     pGlobalSize,
			     pLocalSize,
			     0,
			     NULL,
			     &tEvent);
      
      clFinish(oclContext->oclCommandQueue);

      //update the request status to each thread
      for (uint i = 0; i < uiReqCount; ++i)
	{
	  TFid tFid       = pOclReqQueue[i].tFid;
	  cl_uint uiReqId = pOclReqQueue[i].uiReqId;

	  (tFid->pThreadRequest[uiReqId]).uiFlags = pOclReqQueue[i].uiFlags;
	  (tFid->pThreadRequest[uiReqId]).pStatus = pOclReqQueue[i].pStatus;

	  tFid->uiReqCount--;	  
	}
      
      dwWaitStatus = WaitForSingleObject(tCloseThreadEvent,0);
    }

  return HTS_OK;
}

DWORD WINAPI dwCFrontThreadStub(LPVOID pParam)
{
  CFrontEnd* pLParam = static_cast<CFrontEnd*>(pParam);

  return pLParam->dwCFrontThread();
}
