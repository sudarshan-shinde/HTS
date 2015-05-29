
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

/*
** bAdd:
** a work-group level function. searches for uiKey in the set. 
** returns a node pNode such that next node's maximum key >= uiKey.
** also returns index in pIndex if the key is found.
** returns true is uiKey is found.
*/

bool bAdd(uint      uiKey,
	  TLLNode*  pNodePool,
	  uint      uiReadIndex,
	  uint*     pWriteIndex)
{
  bool bFoundKey;
  bool bAddedKey;
  uint uiPPtr;
  uint uiIndex;
  
  uint lid = get_local_id(0);

  return true;
  
  //find the node after with the key is supposed to go.
  bFoundKey = bFind(uiKey, pNodePool, pWriteIndex, &uiPPtr, &uiIndex);
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  if(bFoundKey == true)
    return false;

  //proceed to add
  uint uiCMPtr = pNodePool[uiPPtr].uiNext;
  uint uiCPtr  = GET_PTR(uiCMPtr);
  uint uiPBit  = GET_DBIT(uiCMPtr);

  if (uiPBit == 0)
    {
      if(uiCPtr != 0)
	{
	  //check for an empty slot
	  uint uiMaxEmptySlot;
	  uint uiVal = pNodePool[uiCPtr].pE[lid];

	  if(uiVal == EMPTY_KEY)
	    {
	      uiMaxEmptySlot = lid + 1;
	    }
	  else
	    {
	      uiMaxEmptySlot = 0;
	    }

	  uiMaxEmptySlot = work_group_reduce_max(uiMaxEmptySlot);

	  if(uiMaxEmptySlot > 0)
	    {
	      if (lid == uiMaxEmptySlot -1)
		{
		  atomic_uint *pChgPtr =
		    (atomic_uint *)(&(pNodePool[uiCPtr].pE[lid]));

		  bAddedKey = atomic_compare_exchange_strong
		                 (pChgPtr,
				  &uiVal, 
				  uiKey); 
		}
	      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	      bAddedKey = work_group_broadcast(bAddedKey, uiMaxEmptySlot -1);

	      return bAddedKey;
	    }
	  else
	    {
	      return false;
	    }
	}
      else
	{
	  //get a node allocated
	  if(lid == 0)
	    {
	      uint uiNewPtr  = uiAlloc(pNodePool,uiReadIndex);
	      uint uiNewMPtr = SET_PTR(uiNewPtr);
	      
	      pNodePool[uiNewPtr].pE[0] = uiKey;
		
	      atomic_uint* pChgPtr =
		(atomic_uint *)(&(pNodePool[uiPPtr].uiNext));
	      
	      bAddedKey = atomic_compare_exchange_strong
		                 (pChgPtr,
				  &uiCMPtr, 
				  uiNewMPtr); 
	    }
	  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	  bAddedKey = work_group_broadcast(bAddedKey,0);

	  return bAddedKey;
	}
    }

  return false;
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
  bool bReqStatus;
  
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

      uiKey   = pOclReqQueue[grid].uiKey; 
      uiType  = pOclReqQueue[grid].uiType;
      uiFlags = pOclReqQueue[grid].uiFlags;
      
      uint uiNode,uiIndex;

      if(uiType == HTS_REQ_TYPE_FIND)
	{
	  bReqStatus = false;
	  //bReqStatus = bFind(uiKey,
	  //		     pNodePool,
	  //		     &(pMiscData->uiWriteIndex),
	  //		     &uiNode,
	  //		     &uiIndex);
	}
      else if(uiType == HTS_REQ_TYPE_ADD)
	{
	  //bReqStatus = bAdd(uiKey,
	  //		    pNodePool,
	  //		    pMiscData->uiReadIndex,
	  //		    &(pMiscData->uiWriteIndex));
	  bReqStatus = true;
	}
      
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      
      if(bReqStatus == true)
	uiIndex = 1;
      else
	uiIndex = 0;
      
      if(lid == 0)
	{
	  uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
	  pOclReqQueue[grid].uiFlags  = uiFlags;
	  pOclReqQueue[grid].uiStatus = uiKey;
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
    }
}


/*
** bRemove:
** a work-group level function. searches for uiKey in the set. 
** if uiKey is found removes it. if not found returns false.
*/

/***
bool bRemove(uint      uiKey,
	     TLLNode*  pNodePool)
{
  //find the key
  uint uiPPtr,uiIndex;
  uint uiVal;
  uint uiCMPtr,uiCPtr,uiDBit; 
  bool bKeyFound;

  bKeyFound = bFind(uiKey,pNodePool,&uiPPtr,&uiIndex);

  if(bKeyFound == true)
    {
      //put EMPTY_KEY in place of uiKey
      uiCMPtr = pNodePool[uiPPtr].uiNext;
      uiCPtr  = GET_PTR(uiCMPtr);
      uiDBit  = GET_DBIT(uiCMPtr);

      if((uiCPtr != 0) && (uiDBit == 0))
	{
	  if(lid == uiIndex -1)
	    {
	      uiVal = pNodePool[uiCPtr].pE[lid];
	      if(uiVal == uiKey)
		{
		  bKeyFound = atomic_compare_exchange_strong
		    ((atomic_int *)(&(pNodePool[uiCPtr].pE[lid])),
		     &uiVal,
		     EMPTY_KEY);
		}
	      else
		{
		  bKeyFound = false;
		}
	    }
	  work_group_barrier(CLK_GLOBAL_MEM_FENCE);
	  bKeyFound = work_group_broadcast(bKeyFound,(uiIndex -1));

	  //if all keys are EMPTY_KEYS mark the node
	  uiVal = pNodePool[uiCPtr].pE[lid];
	  uiVal = work_group_all(uiVal == EMPTY_KEY);
	  if(uiVal)
	    {
	      if(lid == 0)
		{
		  uiNMPtr  = pNodePool[uiCPtr].uiNext;
		  uiNSMPtr = SET_DBIT(uiNMPtr);
		  atomic_compare_exchange_strong
		    ((atomic_int *)(&(pNodePool[uiCPtr].uiNext)),
		     &uiNMPtr,
		     uiNSMPtr);
		  
		}
	      work_group_barrier(CLK_GLOBAL_MEM_FENCE);
	    }
	}
      else
	{
	  bKeyFound = false;
	}
    }

  return bKeyFound;
}

***/

