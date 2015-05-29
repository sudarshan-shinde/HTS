
#define _OCL_CODE_
#include "HTSShared.hpp"

/*
** uiAlloc:
** a thread level function, to get an empty node from node pool pointed by
** pNodePooHead. 
**
*/
uint uiAlloc(TLLNode* pNodePool, uint uiReadIndex)
{
  uint uiLLNode;
  bool bFoundNode = false;

  while(bFoundNode != true)
    {
      uiLLNode = pNodePool[uiReadIndex].uiNext;
      if(uiLLNode != 0)
	{
	  uint uiLLNextNode = pNodePool[uiLLNode].uiNext;
	  atomic_uint* pChgPtr =
	    (atomic_uint *)(&(pNodePool[uiReadIndex].uiNext)); 
	  bFoundNode = atomic_compare_exchange_strong
	        	    (pChgPtr,
			     &uiLLNode,
			     uiLLNextNode);
	}
      else
	{
	  bFoundNode = true;
	}
    }
  return uiLLNode;
}

/*
** uiFree:
** a thread level function, to put a node uiLLNode back to the node pool 
** pointed by pNodePooHead. 
**
*/
uint uiFree(TLLNode* pNodePool, uint* pWriteIndex, uint uiLLNode)
{
  bool bFoundNode      =  false;
  
  while(bFoundNode != true)
    {
      uint uiWriteIndexIn  = *pWriteIndex;
      uint uiLLNextNode    = pNodePool[uiWriteIndexIn].uiNext;
      atomic_uint* pChgPtr =
	(atomic_uint *)(&(pNodePool[uiWriteIndexIn].uiNext));
			
      pNodePool[uiLLNode].uiNext = uiLLNextNode;

      bFoundNode = atomic_compare_exchange_strong
			(pChgPtr,
			 &uiLLNextNode,
			 uiLLNode);
    }

  bool bUpdatedIndex   = false;

  while(bUpdatedIndex != true)
    {
      uint uiWriteIndexIn  = *pWriteIndex;    
      uint uiLLNextNode    = pNodePool[uiWriteIndexIn].uiNext;
      uint uiWriteIndex;
      
      while(uiLLNextNode != 0)
	{
	  uiWriteIndex = uiLLNextNode;
	  uiLLNextNode = pNodePool[uiWriteIndex].uiNext;      
	}
      atomic_uint* pChgPtr = (atomic_uint *)pWriteIndex;

      bUpdatedIndex = atomic_compare_exchange_strong
	                (pChgPtr,
			 &uiWriteIndexIn,
			 uiWriteIndex);
    }
  return uiLLNode;
}

/*
** uiHashFunction:
** hash function to map key to hash table index.
** 
**
*/
uint uiHashFunction(uint uiKey)
{
  return uiKey & OCL_HASH_TABLE_MASK;
}

/*
** bDeleteMakredNodes:
** thread level function
** deletes all the makred nodes next to uiPPtr
** 
**
*/
bool bDelMarkedNodes(uint uiPPtr, TLLNode* pNodePool, uint* pWriteIndex)
{
  uint uiCMPtr, uiCPtr, uiPBit;
  uint uiNMPtr, uiNPtr, uiCBit;
  uint uiNewCMPtr;
  bool bCASStatus;

  //TLLNode* pNodePoolHead = pNodePool + OCL_HASH_TABLE_SIZE;
  
  //remove all marked nodes after uiPPtr
  bool bAllMarkedDeleted = false;
  while(bAllMarkedDeleted != true)
    {
      uiCMPtr  = pNodePool[uiPPtr].uiNext;
      uiCPtr   = GET_PTR(uiCMPtr);
      uiPBit   = GET_DBIT(uiCMPtr);
      
      if((uiCPtr != 0) && (uiPBit == 0))
	{
	  uiNMPtr  = pNodePool[uiCPtr].uiNext;
	  uiNPtr   = GET_PTR(uiCMPtr);
	  uiCBit   = GET_PTR(uiCMPtr);
	  
	  if(uiCBit)
	    {
	      atomic_uint* pChgPtr
		= (atomic_uint *)(&(pNodePool[uiPPtr].uiNext));
	      
	      uiNewCMPtr = SET_PTR(uiNPtr);
	      bCASStatus = atomic_compare_exchange_strong
		            (pChgPtr,
			     &(uiCMPtr),
			     uiNewCMPtr);

	      if(bCASStatus)
		{
		  uiFree(pNodePool, pWriteIndex, uiCPtr);
		}
	    }
	  else
	    {
	      bAllMarkedDeleted = true;
	    }
	}
      else
	{
	  bAllMarkedDeleted = true;
	}
    }

  return true;
}

/*
** bFind:
** a work-group level function. searches for uiKey in the set. 
** returns a node pNode such that next node's maximum key >= uiKey.
** also returns index in pIndex if the key is found.
** returns true is uiKey is found.
*/

bool bFind(uint      uiKey,
	   TLLNode*  pNodePool,
	   uint*     pWriteIndex,
	   uint*     pNode,
	   uint*     pIndex)
{
  uint uiCMPtr, uiCPtr, uiPBit;
  
  //get the thread id
  uint lid         = get_local_id(0);

  //get the starting node
  uint uiPPtr      = uiHashFunction(uiKey);

  //loop through to find the node.
  bool bNodeFound  = false;
  bool bKeyFound   = false;
  
  while(bNodeFound != true)
    {
      if (lid == 0)
	{
	  bDelMarkedNodes(uiPPtr,pNodePool,pWriteIndex);
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE);

      uiCMPtr  = pNodePool[uiPPtr].uiNext;
      uiCPtr   = GET_PTR(uiCMPtr);
      uiPBit   = GET_DBIT(uiCMPtr);

      // if the current node is null return prev ptr
      if((uiCPtr != 0) && (uiPBit == 0))
	{
	  uint uiVal    = pNodePool[uiCPtr].pE[lid];
	  uint uiMaxVal = work_group_reduce_max(uiVal);

	  if(uiMaxVal >= uiKey)
	    {
	      //check if the key is found
	      uint uiIndex;
	      if(uiKey == uiVal)
		uiIndex = lid + 1;
	      else
		uiIndex = 0;

	      uiIndex = work_group_reduce_max(uiIndex);
	      
	      *pNode     = uiPPtr;
	      *pIndex    = uiIndex;

	      if(uiIndex)
		bKeyFound = true;
	      
	      bNodeFound = true;
	    }
	  else
	    {
	      uiPPtr = uiCPtr;
	    }
	}
      else
	{
	  *pNode     = uiPPtr;
	  *pIndex    = 0;
	  bNodeFound = true;
	}
    }

  return bKeyFound;
}

__kernel void HTSTopKernel(__global void* pvOclReqQueue,
			   __global void* pvNodePool,
			   __global void* pvMiscData,
			   uint  uiReqCount)
{
  uint uiFlags;
  uint uiKey;
  uint uiStatus;
  uint uiType;
  
  //get the svm data structures
  TQueuedRequest* pOclReqQueue = (TQueuedRequest *)pvOclReqQueue;
  TLLNode*        pNodePool    = (TLLNode *)pvNodePool;
  //TLLNode*        pHashTable   = (TLLNode *)pvHashTable;  
  TMiscData*      pMiscData    = (TMiscData*)pvMiscData;
  
  uint grid = get_group_id(0);
  uint lid  = get_local_id(0);
  
  if (grid < uiReqCount)
    {
      //if(lid == 0)
      //{
      //  uint uiNode = uiAlloc(pNodePool,pMiscData->uiReadIndex);
	  
      //  uiFlags = pOclReqQueue[grid].uiFlags;
      //  uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
      //  pOclReqQueue[grid].uiFlags  = uiFlags;
      //  pOclReqQueue[grid].uiStatus = uiNode;

      //  uiFree(pNodePool,
      //	 &(pMiscData->uiWriteIndex),
      //	 uiNode);
      //}

      uiKey  = pOclReqQueue[grid].uiKey; 
      uiType = pOclReqQueue[grid].uiType;

      uint uiNode,uiIndex;
      
      bool bFound = bFind(uiKey,
			  pNodePool,
			  &(pMiscData->uiWriteIndex),
			  &uiNode,
			  &uiIndex);

      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);      
      if(lid == 0)
	{
	  uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
	  pOclReqQueue[grid].uiFlags  = uiFlags;
	  pOclReqQueue[grid].uiStatus = uiIndex;
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
    }
}

