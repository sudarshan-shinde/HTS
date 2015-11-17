#include "HTSFrontEnd.hpp"

DWORD WINAPI dwCFrontThreadStub(LPVOID pParam);
  
CFrontEnd::CFrontEnd()
{
  //initialize variables
  uiTidCount  = 0;
  uiReqCount  = 0;
  pOclContext = NULL;
}

CFrontEnd::~CFrontEnd()
{
  //terminate the thread
  //SetEvent(tCloseThreadEvent);
  //WaitForSingleObject(tThreadHandle,INFINITE);

  //close the event
  //CloseHandle(tCloseThreadEvent);
}

UINT CFrontEnd::uiOpenFrontEnd()
{
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

  return HTS_OK;
}

UINT CFrontEnd::uiCloseFrontEnd()
{
  //terminate the thread
  SetEvent(tCloseThreadEvent);
  //ResetEvent(tCloseThreadEvent);
  WaitForSingleObject(tThreadHandle,INFINITE);

  //close the event
  CloseHandle(tCloseThreadEvent);

  return HTS_OK;
}

UINT CFrontEnd::uiBindOCLContext(TOclContext* pOclContextIn)
{
  pOclContext = pOclContextIn;
  return HTS_OK;
}

UINT CFrontEnd::uiBuildOCLKernels()
{
  //allocate the required memeory
  size_t           uiReqQueueSize  = OCL_REQ_QUEUE_SIZE*sizeof(TQueuedRequest);
  size_t           uiNodePoolSize  = OCL_NODE_POOL_SIZE*sizeof(TLLNode);
  size_t           uiHashTableSize = OCL_HASH_TABLE_SIZE*sizeof(TLLNode);
  size_t           uiMiscDataSize  = sizeof(TMiscData);
  
  size_t           uiSVMSize = uiReqQueueSize  + 
                               uiNodePoolSize  + 
                               uiHashTableSize +
                               uiMiscDataSize;
  
  cl_svm_mem_flags tSVMFlags = CL_MEM_READ_WRITE |
                               CL_MEM_SVM_FINE_GRAIN_BUFFER;
                               //CL_MEM_SVM_ATOMICS;
  
  pSVMBuf     = (void *)clSVMAlloc(pOclContext->oclContext,
				   tSVMFlags,
				   uiSVMSize,
				   0);
  if(pSVMBuf == NULL)
    {
      std::cout << "SVMAlloc failed." << std::endl;
      return HTS_NOT_OK;
    }
  
  //allocate different svm pointers
  pOclReqQueue = (TQueuedRequest *)pSVMBuf;
  pHashTable   = (TLLNode*)((char *)pOclReqQueue + uiReqQueueSize);
  pNodePool    = (TLLNode*)((char *)pHashTable   + uiHashTableSize);
  pMiscData    = (TMiscData*)((char *)pNodePool  + uiNodePoolSize);

  //make node pool and hash table to be same

  pNodePool    = pHashTable;
  
  //initialize svm buffers
  for(UINT i = 0; i < OCL_HASH_TABLE_SIZE; ++i)
    {
      pNodePool[i].uiNext = 0;
    }

  cl_uint uiStartIndex = OCL_HASH_TABLE_SIZE + 1;
  cl_uint uiEndIndex   = OCL_HASH_TABLE_SIZE + OCL_NODE_POOL_SIZE;

  for(cl_uint i = uiStartIndex; i < uiEndIndex; ++i)
    {
      cl_uint j = SET_MPTR((i+1),1);
      pNodePool[i].uiNext = j;
    }
  
  pNodePool[uiEndIndex].uiNext              = 0;

  pMiscData->uiPoolHead                     = OCL_HASH_TABLE_SIZE;
  pNodePool[pMiscData->uiPoolHead].uiNext   = SET_MPTR(uiStartIndex,1);

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

  std::cout << "building program" << std::endl;

  const char* options = "-I. -cl-std=CL2.0";
  iStatus = clBuildProgram(oclProgram,
			   1,
			   pOclContext->pOclDevices,
			   options,
			   NULL,
			   NULL);
				 
  if(iStatus != CL_SUCCESS)
    {
      //get the build error
      size_t uiBuildLogSize;
      clGetProgramBuildInfo(oclProgram,
			    pOclContext->pOclDevices[0],
			    CL_PROGRAM_BUILD_LOG,
			    0,
			    NULL,
			    &uiBuildLogSize);

      char *pBuildLog = (char *)malloc(uiBuildLogSize*sizeof(char));

      clGetProgramBuildInfo(oclProgram,
			    pOclContext->pOclDevices[0],
			    CL_PROGRAM_BUILD_LOG,
			    uiBuildLogSize,
			    (void *)pBuildLog,
			    NULL);


      std::cout << "failed to build program." << std::endl;
      std::cout << "BUILD LOG---" << std::endl;
      std::cout << pBuildLog << std::endl;
      std::cout << "------------" << std::endl;
      return HTS_NOT_OK;
    }

  /* create kernels */
  std::cout << "creating kernels" << std::endl;  
  oclKernel = clCreateKernel(oclProgram,
			     "HTSTopKernel",
			     NULL);  
  
  return HTS_OK;
}

UINT CFrontEnd::uiReleaseOCLKernels()
{
  if(pOclReqQueue)
    clSVMFree(pOclContext->oclContext, pSVMBuf);

  clReleaseKernel(oclKernel);
  clReleaseProgram(oclProgram);

  return HTS_OK;
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
      cl_uint uiFlags = (tFid->pThreadRequest[uiReqId]).uiFlags;
      if(uiFlags & HTS_REQ_FULL)
	{
	  uiReqId++;
	}
      else
	{
	  bFoundFlag = true;
	}
    }

  /* DEBUG 
  std::cout << "putting into private list..." << std::endl;
   DEBUG */
  
  //put the request in private list
  tFid->pThreadRequest[uiReqId].uiType   = cReq.uiType;  
  tFid->pThreadRequest[uiReqId].uiKey    = cReq.uiKey;
  tFid->pThreadRequest[uiReqId].uiFlags  = cReq.uiFlags;
  tFid->pThreadRequest[uiReqId].uiStatus = cReq.uiStatus;

  (tFid->pThreadRequest[uiReqId]).uiFlags |= HTS_REQ_FULL; 
  tFid->uiReqCount++;

  //set the request as queued.
  (tFid->pThreadRequest[uiReqId]).uiFlags |= HTS_REQ_QUEUED; 
  tEvent                                   = uiReqId;

  //if a request slot is found, put request in the queue
  TQueuedRequest cQReq;
  cQReq.tFid     = tFid;
  cQReq.uiReqId  = uiReqId;
  cQReq.uiType   = cReq.uiType;  
  cQReq.uiKey    = cReq.uiKey;
  cQReq.uiFlags  = (tFid->pThreadRequest[uiReqId]).uiFlags;
  cQReq.uiStatus = cReq.uiStatus;

  /* DEBUG */
  std::cout << "submit:" << cQReq.uiKey << std::endl;
  /* DEBUG */
  
  if(tReqQueue.uiPut(&cQReq) != HTS_OK)
    {
      (tFid->pThreadRequest[uiReqId]).uiFlags = 0; 
      tFid->uiReqCount--;

      return HTS_NOT_OK;
    }

  /* DEBUG */
  //std::cout << "req id:" << uiReqId << std::endl;
  //std::cout << "internal flag:" << (tFid->pThreadRequest[uiReqId]).uiFlags ;
  //std::cout << std::endl;
  /* DEBUG */

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

cl_uint CFrontEnd::uiGetStatus(TFid tFid, TEvent tEvent, cl_uint* pStatus)
{
  cl_uint  uiReqId   = (cl_uint)tEvent;
  cl_uint  uiFlags   = (tFid->pThreadRequest[uiReqId]).uiFlags;
  cl_uint  uiRStatus = (tFid->pThreadRequest[uiReqId]).uiStatus;

  /* EDBG */
  //std::cout << "status:" << uiFlags << std::endl;
  /* EDBG */

  //std::cout << "uiRStatus:" << uiRStatus << std::endl;
  
  *pStatus = 0;
  if(uiFlags & HTS_REQ_COMPLETED)
    {
      (tFid->pThreadRequest[uiReqId]).uiFlags = 0;
      *pStatus   = uiRStatus;
      return HTS_REQ_COMPLETED;
    }

  if(uiFlags & HTS_REQ_ABORTED)
    {
      (tFid->pThreadRequest[uiReqId]).uiFlags = 0;
      *pStatus   = uiRStatus;
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
  size_t   pLocalSize[1]  = {OCL_WG_SIZE};
  size_t   pGlobalSize[1] = {OCL_WG_SIZE};
  
  DWORD    dwWaitStatus   = WaitForSingleObject(tCloseThreadEvent,0);

  while(dwWaitStatus == WAIT_TIMEOUT)
    {
      //service the queued requests
      TQueuedRequest cQReq;
      BOOL           bSubmitFlag = FALSE;
      UINT           uiReqCount  = 0;      

      while(bSubmitFlag == FALSE)
	{
	  if(uiReqCount < OCL_REQ_QUEUE_SIZE)
	    {
	      if(tReqQueue.uiGet(&cQReq) == HTS_OK)
		{
		  pOclReqQueue[uiReqCount].tFid     = cQReq.tFid;
		  pOclReqQueue[uiReqCount].uiReqId  = cQReq.uiReqId;
		  pOclReqQueue[uiReqCount].uiType   = cQReq.uiType;	  
		  pOclReqQueue[uiReqCount].uiKey    = cQReq.uiKey;
		  pOclReqQueue[uiReqCount].uiFlags  = cQReq.uiFlags;
		  pOclReqQueue[uiReqCount].uiStatus = cQReq.uiStatus;

		  //std::cout << "k:" << pOclReqQueue[uiReqCount].uiKey;
		  uiReqCount++;
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

      //std::cout << "submitting request:" << uiReqCount << std::endl;
      
      //submit all requests to GPU
      if(uiReqCount > 0)
	{
	  UINT uiGlobalSize = uiReqCount*OCL_WG_SIZE;

	  pGlobalSize[0] = (size_t)(uiGlobalSize);
	  pLocalSize[0]  = OCL_WG_SIZE;
      
	  clSetKernelArgSVMPointer(oclKernel,
	  			   0,
	  			   (void *)(pOclReqQueue));
	  //clSetKernelArgSVMPointer(oclKernel,
	  //			   1,
	  //			   (void *)(pHashTable));
	  clSetKernelArgSVMPointer(oclKernel,
	  			   1,
	  			   (void *)(pNodePool));
	  clSetKernelArgSVMPointer(oclKernel,
	  			   2,
	  			   (void *)(pMiscData));
	  clSetKernelArg(oclKernel,
	  		 3,
	  		 sizeof(cl_uint),
	  		 (void *)(&uiReqCount));
	  clEnqueueNDRangeKernel(pOclContext->oclCommandQueue,
	  			 oclKernel,
	  			 1,
	  			 NULL,
	  			 pGlobalSize,
	  			 pLocalSize,
	  			 0,
	  			 NULL,
	  			 NULL);
	  
	  clFinish(pOclContext->oclCommandQueue);
	  //std::cout << "finished kernel." << std::endl;
	}
      
      //update the request status to each thread
      for (unsigned int i = 0; i < uiReqCount; ++i)
	{
	  TFid tFid       = pOclReqQueue[i].tFid;
	  cl_uint uiReqId = pOclReqQueue[i].uiReqId;

	  //(tFid->pThreadRequest[uiReqId]).uiFlags 
	  //= pOclReqQueue[i].uiFlags | HTS_REQ_COMPLETED;
	  
	  /* DEBUG 
	  std::cout << i << ":";
	  std::cout << (long)(tFid) << ":";
	  std::cout << uiReqId << ":";
	  std::cout << ((tFid->pThreadRequest[uiReqId]).uiFlags) << ":";
	  std::cout << ((tFid->pThreadRequest[uiReqId]).uiStatus) << std::endl;  	   DEBUG */

	  /* DEBUG */
	  //std::cout << "key:" << pOclReqQueue[i].uiKey << std::endl;
	  //std::cout << "sts:" << pOclReqQueue[i].uiStatus << std::endl;
	  /* DEBUG */
	  
	  (tFid->pThreadRequest[uiReqId]).uiStatus = pOclReqQueue[i].uiStatus;

	  (tFid->pThreadRequest[uiReqId]).uiFlags 
	     = pOclReqQueue[i].uiFlags;
	  
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
