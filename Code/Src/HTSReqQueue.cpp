
#include "HTSReqQueue.hpp"

#include <iostream>

CRequestQueue::CRequestQueue()
{
  uiReadIndex  = 0;
  uiWriteIndex = 1;
}

CRequestQueue::~CRequestQueue()
{
}

LONG CRequestQueue::uiPut(TQueuedRequest* pReq)
{
  //get the read and write index
  LONG uiLWriteIndex   = uiWriteIndex;
  LONG uiIncWriteIndex = (uiLWriteIndex + 1) & REQ_QUEUE_SIZE_MASK;
 
  if(uiIncWriteIndex == uiReadIndex)
    return HTS_NOT_OK;
  
  //claim the index
  LONG* pWriteIndex = (LONG*)(&uiWriteIndex);
  
  InterlockedCompareExchange(pWriteIndex,
			     uiIncWriteIndex,
			     uiLWriteIndex);

  if(*pWriteIndex != uiIncWriteIndex)
    return HTS_NOT_OK;

  /* DEBUG 
  std::cout << "W:" << uiLWriteIndex << std::endl;
   DEBUG */

  //copy the request to the queue
  pReqQueue[uiLWriteIndex].tFid    = pReq->tFid;
  pReqQueue[uiLWriteIndex].uiReqId = pReq->uiReqId;
  pReqQueue[uiLWriteIndex].uiFlags = pReq->uiFlags;
  pReqQueue[uiLWriteIndex].pStatus = pReq->pStatus;

  //set the flag
  pReqQueue[uiLWriteIndex].uiFlags |= HTS_REQ_QUEUED; 

  /* DEBUG 
  std::cout << "WD:" << std::endl;
   DEBUG */

  return HTS_OK;
}

LONG CRequestQueue::uiGet(TQueuedRequest* pReq)
{
  //get the read and write index
  LONG uiLReadIndex    = uiReadIndex;
  LONG uiIncReadIndex  = (uiLReadIndex + 1) & REQ_QUEUE_SIZE_MASK;
 
  if(uiIncReadIndex == uiWriteIndex)
    return HTS_NOT_OK;

  //check if the record has been completely written
  if(!(pReqQueue[uiIncReadIndex].uiFlags & HTS_REQ_QUEUED))
    return HTS_NOT_OK;

  /* DEBUG 
  std::cout << "R:" << uiIncReadIndex << std::endl;
   DEBUG */
  
  //copy the request to the queue
  pReq->tFid    = pReqQueue[uiIncReadIndex].tFid;
  pReq->uiReqId = pReqQueue[uiIncReadIndex].uiReqId;
  pReq->uiFlags = pReqQueue[uiIncReadIndex].uiFlags;
  pReq->pStatus = pReqQueue[uiIncReadIndex].pStatus;

  //set the flag to empty
  pReqQueue[uiIncReadIndex].uiFlags = 0;

  //increment read index
  uiReadIndex = uiIncReadIndex;

  /* DEBUG 
  std::cout << "RD:" << std::endl;
   DEBUG */

  return HTS_OK;
}
