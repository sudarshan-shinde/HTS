#include "Test.hpp"

DWORD WINAPI dwThreadFn(LPVOID pInParam)
{
  CThrParam* pParam      = static_cast<CThrParam*>(pInParam);
  CFrontEnd* pFrontEnd   = pParam->pFrontEnd;
  uint       uiId        = pParam->uiId;  
  uint       uiReqType   = pParam->uiReqType;
  uint       uiKeyStart  = pParam->uiKeyStart;
  uint       uiKeyEnd    = pParam->uiKeyEnd;
  uint       uiOrder     = pParam->uiOrder;
  bool       bVerbose    = pParam->bVerbose;
  
  /* DEBUG 
  std::cout << "T:" << uiId << "[" << uiKeyStart << "-" << uiKeyEnd;
  std::cout << std::endl;
   DEBUG */  
  
  /* sanity check on inputs */
  if((uiKeyStart <= 0)||(uiKeyEnd <= 0))
    {
      std::cout << "T:" << uiId;
      std::cout << "Only positive keys are allowed." << std::endl;
      return TEST_NOT_OK;
    }

  if(uiOrder == TEST_ASCENDING_ORDER)
    {
      if(uiKeyStart >= uiKeyEnd)
	{
	  std::cout << "T:" << uiId;
	  std::cout << "start should be less than end for ascending order.";
	  std::cout << std::endl;
	  return TEST_NOT_OK;
	}
    }

  if(uiOrder == TEST_DESCENDING_ORDER)
    {
      if(uiKeyStart <= uiKeyEnd)
	{
	  std::cout << "T:" << uiId;
	  std::cout << "start should be more than end for descending order.";
	  std::cout << std::endl;
	  return TEST_NOT_OK;
	}
    }

  /* register the thread with front end */
  TFid tFid = pFrontEnd->tRegister();

  CRequest tReq;
  TEvent   tReqEvent;

  uint uiStatus = TEST_OK;
  uint uiCount  = 0;
  if(uiOrder == TEST_ASCENDING_ORDER)
    {
      for(uint i = uiKeyStart; i <= uiKeyEnd; ++i)
	{
	  tReq.uiType  = uiReqType; 
	  tReq.uiKey   = i;
	  tReq.uiFlags = HTS_REQ_BLOCKING;
	  
	  if(pFrontEnd->uiSubmitReq(tFid, tReq, tReqEvent) == HTS_OK)
	    {
	      cl_uint uiReqCode, uiReqStatus;
	      uiReqCode = pFrontEnd->uiGetStatus(tFid,tReqEvent,uiReqStatus); 
	      if(uiReqCode == HTS_REQ_COMPLETED)
		{
		  if (uiReqStatus == HTS_ATTEMPT_FAILED)
		    uiStatus = TEST_ATTEMPT_FAILED;
		  else if(uiReqStatus == HTS_FAILURE)
		    uiStatus = TEST_OPENCL_ERROR;		
		}
	      else
		{
		  uiStatus = TEST_REQ_ABORTED;
		}
	    }
	  else
	    {
	      uiStatus = TEST_SUBMIT_FAILED;	      
	    }

	  if(bVerbose)
	    {
	      switch(uiStatus)
		{
		case TEST_SUBMIT_FAILED:
		  std::cout << "T:" << uiId << ":SF:" << i << std::endl;
		  break;
		case TEST_REQ_ABORTED:
		  std::cout << "T:" << uiId << ":RF:" << i << std::endl;	
		  break;
		case TEST_ATTEMPT_FAILED:
		  std::cout << "T:" << uiId << ":AF:" << i << std::endl;	
		  break;
		case TEST_OPENCL_ERROR:
		  std::cout << "T:" << uiId << ":OF:" << i << std::endl;	
		  break;
		default:
		  break;
		}
	    }
	  
	  if(uiStatus != TEST_OK)
	    {
	      uiCount++;
	      uiStatus = TEST_OK;
	    }
	}
    }

  if(uiOrder == TEST_DESCENDING_ORDER)
    {
      for(uint i = uiKeyStart; i >= uiKeyEnd; --i)
	{
	  tReq.uiType  = uiReqType; 
	  tReq.uiKey   = i;
	  tReq.uiFlags = HTS_REQ_BLOCKING;
	  
	  if(pFrontEnd->uiSubmitReq(tFid, tReq, tReqEvent) == HTS_OK)
	    {
	      cl_uint uiReqCode, uiReqStatus;
	      uiReqCode = pFrontEnd->uiGetStatus(tFid,tReqEvent,uiReqStatus); 
	      if(uiReqCode == HTS_REQ_COMPLETED)
		{
		  if (uiReqStatus == HTS_ATTEMPT_FAILED)
		    uiStatus = TEST_ATTEMPT_FAILED;
		  else if(uiReqStatus == HTS_FAILURE)
		    uiStatus = TEST_OPENCL_ERROR;		
		}
	      else
		{
		  uiStatus = TEST_REQ_ABORTED;
		}
	    }
	  else
	    {
	      uiStatus = TEST_SUBMIT_FAILED;	      
	    }
	  
	  if(bVerbose)
	    {
	      switch(uiStatus)
		{
		case TEST_SUBMIT_FAILED:
		  std::cout << "T:" << uiId << ":SF:" << i << std::endl;
		  break;
		case TEST_REQ_ABORTED:
		  std::cout << "T:" << uiId << ":RF:" << i << std::endl;	
		  break;
		case TEST_ATTEMPT_FAILED:
		  std::cout << "T:" << uiId << ":AF:" << i << std::endl;	
		  break;
		case TEST_OPENCL_ERROR:
		  std::cout << "T:" << uiId << ":OF:" << i << std::endl;	
		  break;
		default:
		  break;
		}
	    }

	  if(uiStatus != TEST_OK)
	    {
	      uiCount++;
	      uiStatus = TEST_OK;
	    }
	}
    }

  //std::cout << "T:" << uiId << "FF:" << uiCount << std::endl;
  
  pFrontEnd->uiDeRegister(tFid);
  
  return TEST_OK;
}


/***
 * connects HTS FrontEnd to the OCL context.
 ***/
uint uiFrontEndOcl(CFrontEnd* pFrontEnd, TOclContext* pOclContext)
{
  /* bind context */
  if(pFrontEnd->uiBindOCLContext(pOclContext) != HTS_OK)
    {
      std::cout << "failed to bind OCL context." << std::endl;
      return TEST_NOT_OK;
    }
  
  /* build OCL kernels */
  if(pFrontEnd->uiBuildOCLKernels() != HTS_OK)
    {
      std::cout << "failed to build OCL kernels." << std::endl;
      return TEST_NOT_OK;
    }

  return TEST_OK;
}

/***
 * Create multiple application threads 
 ***/
uint uiCreateApplThreads(CThrParam* pThrParam)
{
  HANDLE           tThreadHandle[TEST_THREADS];
  DWORD            dwThreadId[TEST_THREADS];
  //TThreadFnPtr     pThreadFn[TEST_THREADS] = {dwThreadFn,dwThreadFn1};

  for (uint i = 0; i < TEST_THREADS; ++i)
    {
      tThreadHandle[i] = CreateThread(NULL,
				      0,
				      dwThreadFn,
				      static_cast<LPVOID>(pThrParam + i),
				      0,
				      dwThreadId+i);
    }

  WaitForMultipleObjects(TEST_THREADS,tThreadHandle,TRUE,INFINITE);
  
  return TEST_OK;
}

uint  uiPopulateParamAdd(CFrontEnd* pFrontEnd, CThrParam* pThrParam)
{
  /* common initialization */
  for (uint i = 0; i < TEST_THREADS; ++i)
    {
      pThrParam[i].uiId       = i;
      pThrParam[i].uiReqType  = HTS_REQ_TYPE_ADD;
      pThrParam[i].uiKeyStart = 0;
      pThrParam[i].uiKeyEnd   = 0;
      pThrParam[i].uiOrder    = TEST_DESCENDING_ORDER;
      pThrParam[i].bVerbose   = false;
      pThrParam[i].pFrontEnd  = pFrontEnd;
    }

  /* thread specific initializations */
  pThrParam[0].uiKeyEnd   = 5;
  pThrParam[0].uiKeyStart = 15;  

  pThrParam[1].uiKeyEnd   = 2;
  pThrParam[1].uiKeyStart = 10;  

  return TEST_OK;
}

uint  uiPopulateParamFind(CFrontEnd* pFrontEnd, CThrParam* pThrParam)
{
  /* common initialization */
  for (uint i = 0; i < TEST_THREADS; ++i)
    {
      pThrParam[i].uiId       = i;
      pThrParam[i].uiReqType  = HTS_REQ_TYPE_FIND;
      pThrParam[i].uiKeyStart = 0;
      pThrParam[i].uiKeyEnd   = 0;
      pThrParam[i].uiOrder    = TEST_ASCENDING_ORDER;
      pThrParam[i].bVerbose   = true;      
      pThrParam[i].pFrontEnd  = pFrontEnd;
    }

  /* thread specific initializations */
  pThrParam[0].uiKeyEnd   = 20;
  pThrParam[0].uiKeyStart = 5;  

  pThrParam[1].uiKeyEnd   = 10;
  pThrParam[1].uiKeyStart = 1;  

  return TEST_OK;
}

uint  uiPopulateParamRemove(CFrontEnd* pFrontEnd, CThrParam* pThrParam)
{
  /* common initialization */
  for (uint i = 0; i < TEST_THREADS; ++i)
    {
      pThrParam[i].uiId       = i;
      pThrParam[i].uiReqType  = HTS_REQ_TYPE_REMOVE;
      pThrParam[i].uiKeyStart = 0;
      pThrParam[i].uiKeyEnd   = 0;
      pThrParam[i].uiOrder    = TEST_ASCENDING_ORDER;
      pThrParam[i].bVerbose   = true;      
      pThrParam[i].pFrontEnd  = pFrontEnd;
    }

  /* thread specific initializations */
  pThrParam[0].uiKeyEnd   = 8;
  pThrParam[0].uiKeyStart = 5;  

  pThrParam[1].uiKeyEnd   = 9;
  pThrParam[1].uiKeyStart = 6;  

  return TEST_OK;
}

int main(int argc, char* argv[])
{
  /* define OCL context */
  TOclContext tOclContext;
  if (uiGetOCLContext(&tOclContext) != HTS_OK)
    {
      std::cout << "failed to initialize OCL context" << std::endl;
      return TEST_NOT_OK;
    }

  /* define the HTS */
  CFrontEnd tFrontEnd;

  /* bind the front end to OCL context */
  if(uiFrontEndOcl(&tFrontEnd, &tOclContext) != TEST_OK)
    {
      std::cout << "failed to initialize HTS" << std::endl;
      return TEST_NOT_OK;
    }

  /* create the front end thread */
  tFrontEnd.uiOpenFrontEnd();
  
  /* populate the thread parameters */
  CFrontEnd* pFrontEnd = &tFrontEnd;
  CThrParam  pThrParam[TEST_THREADS];

  /* Add some elements to the set */
  std::cout << "ADDING SOME ELEMENTS..." << std::endl;
  uiPopulateParamAdd(pFrontEnd, pThrParam);
  uiCreateApplThreads(pThrParam);
  tFrontEnd.uiInspectElements();

  /* Find some elements in the set */
  std::cout << "FINDING SOME ELEMENTS..." << std::endl;  
  uiPopulateParamFind(pFrontEnd, pThrParam);
  uiCreateApplThreads(pThrParam);
  tFrontEnd.uiInspectElements();

  /* Remove some elements in the set */
  std::cout << "REMOVING SOME ELEMENTS..." << std::endl;    
  uiPopulateParamRemove(pFrontEnd, pThrParam);
  uiCreateApplThreads(pThrParam);
  tFrontEnd.uiInspectElements();

  
  /* close the front end */
  tFrontEnd.uiCloseFrontEnd();

  return TEST_OK;
}


