
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
  uint uiLLMNode, uiLLNode;
  bool bFoundNode = false;

  while(bFoundNode != true)
    {
      uiLLMNode = pNodePool[uiReadIndex].uiNext;
      uiLLNode  = GET_PTR(uiLLMNode);
      if(uiLLNode != 0)
	{
	  uint uiLLMNextNode = pNodePool[uiLLNode].uiNext;
	  atomic_uint* pChgPtr =
	    (atomic_uint *)(&(pNodePool[uiReadIndex].uiNext)); 
	  bFoundNode = atomic_compare_exchange_strong
	        	    (pChgPtr,
			     &uiLLMNode,
			     uiLLMNextNode);
	}
      else
	{
	  bFoundNode = true;
	}
    }
  
  pNodePool[uiLLNode].uiNext = 0;  
  return uiLLNode;
}

/*
** uiFree:
** a thread level function, to put a node uiLLNode back to the node pool 
** pointed by pNodePooHead. 
**
*/
uint uiFree(TLLNode* pNodePool, uint uiWriteIndex, uint uiLLNode)
{
  uint uiLLMLastNode, uiLLLastNode, uiLLMNode;
  
  bool bFoundNode                 =  false;
  pNodePool[uiLLNode].uiNext      = 0;
  
  while(bFoundNode != true)
    {
      uiLLMLastNode    = pNodePool[uiWriteIndex].uiNext;
      uiLLLastNode     = GET_PTR(uiLLMLastNode);
      uiLLMNode        = SET_MPTR(uiLLNode,1);
      
      atomic_uint* pChgPtr =
	(atomic_uint *)(&(pNodePool[uiWriteIndex].uiNext));
			
      bFoundNode = atomic_compare_exchange_strong
			(pChgPtr,
			 &uiLLMLastNode,
			 uiLLMNode);
    }

  pNodePool[uiLLLastNode].uiNext      = uiLLMNode;  
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
bool bDelMarkedNodes(uint uiPPtr, TLLNode* pNodePool, uint uiWriteIndex)
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
		  uiFree(pNodePool, uiWriteIndex, uiCPtr);
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
	   uint      uiWriteIndex,
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
        bDelMarkedNodes(uiPPtr,pNodePool,uiWriteIndex);
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
	  uint      uiWriteIndex)
{
  bool bFoundKey;
  bool bAddedKey;
  uint uiPPtr;
  uint uiIndex;
  
  uint lid = get_local_id(0);

  //return true;
  
  //find the node after with the key is supposed to go.
  bFoundKey = bFind(uiKey, pNodePool, uiWriteIndex, &uiPPtr, &uiIndex);
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
	  uint uiNewPtr;
	  uint uiNewMPtr;
	  if(lid == 0)
	    {
	      uiNewPtr  = uiAlloc(pNodePool,uiReadIndex);
	      uiNewMPtr = SET_PTR(uiNewPtr);
	    }
	  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	  uiNewPtr  = work_group_broadcast(uiNewPtr,0);
	  uiNewMPtr = work_group_broadcast(uiNewMPtr,0);	  
	  pNodePool[uiNewPtr].pE[lid] = EMPTY_KEY;
	  
	  if(lid == 0)
	    {
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
	  //bAddedKey   = false;
	  
	  return bAddedKey;
	}
    }

  return false;
}

/*
** bRemove:
** a work-group level function. searches for uiKey in the set. 
** if uiKey is found removes it. if not found returns false.
*/
bool bRemove(uint      uiKey,
	     TLLNode*  pNodePool,
	     uint      uiReadIndex,
	     uint      uiWriteIndex)
{
  //find the key
  uint uiPPtr,uiIndex;
  uint uiVal;
  uint uiCMPtr,uiCPtr,uiPBit; 
  bool bFoundKey;

  uint lid = get_local_id(0);
  
  //find the node after with the key is supposed to go.
  bFoundKey = bFind(uiKey, pNodePool, uiWriteIndex, &uiPPtr, &uiIndex);
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  if(bFoundKey == false)
    return false;

  //put EMPTY_KEY in place of uiKey
  uiCMPtr = pNodePool[uiPPtr].uiNext;
  uiCPtr  = GET_PTR(uiCMPtr);
  uiPBit  = GET_DBIT(uiCMPtr);
  
  if((uiCPtr != 0) && (uiPBit == 0))
    {
      if(lid == uiIndex -1)
	{
	  uiVal = pNodePool[uiCPtr].pE[lid];
	  if(uiVal == uiKey)
	    {
	      bFoundKey = atomic_compare_exchange_strong
		((atomic_uint *)(&(pNodePool[uiCPtr].pE[lid])),
		 &uiVal,
		 EMPTY_KEY);
	    }
	  else
	    {
	      bFoundKey = false;
	    }
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      bFoundKey = work_group_broadcast(bFoundKey,(uiIndex -1));
      
      //if all keys are EMPTY_KEYS mark the node
      uiVal = pNodePool[uiCPtr].pE[lid];
      uiVal = work_group_all(uiVal == EMPTY_KEY);
      if(uiVal)
	{
	  if(lid == 0)
	    {
	      uint uiNMPtr  = pNodePool[uiCPtr].uiNext;
	      uint uiNSMPtr = SET_DBIT(uiNMPtr);
	      atomic_compare_exchange_strong
		((atomic_uint *)(&(pNodePool[uiCPtr].uiNext)),
		 &uiNMPtr,
		 uiNSMPtr);
	      
	    }
	  work_group_barrier(CLK_GLOBAL_MEM_FENCE);
	}
    }
  else
    {
      bFoundKey = false;
    }
  
  return bFoundKey;
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
  uint            uiReadIndex  = pMiscData->uiReadIndex;
  uint            uiWriteIndex = pMiscData->uiWriteIndex;  
  
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
	  //bReqStatus = false;
	  bReqStatus = bFind(uiKey,
	  		     pNodePool,
	  		     uiWriteIndex,
	  		     &uiNode,
	  		     &uiIndex);
	}
      else if(uiType == HTS_REQ_TYPE_ADD)
	{
	  //bReqStatus = true;
	  bReqStatus = bAdd(uiKey,
	  		    pNodePool,
	  		    uiReadIndex,
	  		    uiWriteIndex);
	}
      else if(uiType == HTS_REQ_TYPE_REMOVE)
	{
	  //bReqStatus = true;
	  bReqStatus = bRemove(uiKey,
			       pNodePool,
			       uiReadIndex,
			       uiWriteIndex);
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
	  pOclReqQueue[grid].uiStatus = uiIndex;
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
    }
}



