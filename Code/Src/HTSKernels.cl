
#define _OCL_CODE_
#include "HTSShared.hpp"

/*
** uiAlloc:
** a thread level function, to get an empty node from node pool pointed by
** pNodePooHead. 
**
*/
uint uiAlloc(TLLNode* pNodePool)
{
  bool bFoundNode = false;

  while(bFoundNode != true)
    {
      uint uiLLNode = pNodePool[0].uiNext;
      if(uiLLNode != 0)
	{
	  uint uiLLNextNode = pNodePool[uiLLNode].uiNext;
	  bFoundNode = atomic_compare_exchange_strong
                  	    ((atomic_int *)(&(pNodePool[0].uiNext)),
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
uint uiFree(TLLNode* pNodePool, uint uiLLNode)
{
  bool bFoundNode = false;

  while(bFoundNode != true)
    {
      uint uiLLNextNode = pNodePool[0].uiNext;
      pNodePool[uiLLNode].uiNext = uiLLNextNode;

      bFoundNode = atomic_compare_exchange_strong
	((atomic_int *)(&(pNodePool[0].uiNext)),
	 &uiLLNextNode,
	 uiLLNode);
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
bool bDelMarkedNodes(uint uiPPtr, TLLNode* pNodePool)
{
  uint uiCMPtr, uiCPtr, uiPBit;
  uint uiNMPtr, uiNPtr, uiCBit;
  uint uiNewCMPtr;
  bool bCASStatus;

  TLLNode* pNodePoolHead = pNodePool + OCL_HASH_TABLE_SIZE;
  
  //remove all marked nodes after uiPNodePtr
  bool bAllMarkedDeleted = false;
  while(bAllMarkedDeleted != true)
    {
      uiCMPtr  = pNodePool[uiPPtr].uiNext;
      uiCPtr   = GET_PTR(uiCMPtr);
      uiPBit   = GET_DBIT(uiCMPtr);
      
      if(uiCPtr != 0)
	{
	  uiNMPtr  = pNodePool[uiCPtr].uiNext;
	  uiNPtr   = GET_PTR(uiCMPtr);
	  uiCBit   = GET_PTR(uiCMPtr);
	  
	  if(uiCBit)
	    {
	      uiNewCMPtr = SET_PTR(uiNPtr);
	      bCASStatus = atomic_compare_exchange_strong
		            ((atmoic_int *)(&(pNodePool[uiPPtr].uiNext)),
			     &(uiCMPtr),
			     uiNewCMPtr);

	      if(bCASStatus)
		{
		  uiFree(pNodePoolHead, uiCPtr);
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
	  bDelMarkedNodes(uiPPtr,pNodePool);
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE);

      uiCMPtr  = pNodePool[uiPPtr].uiNext;
      uiCPtr   = GET_PTR(uiCMPtr);
      uiPBit   = GET_DBIT(uiCMPtr);

      // if the current node is null return prev ptr
      if(uiCPtr != 0)
	{
	  uiVal    = pNodePool[uiCPtr].pE[lid];
	  uiMaxVal = work_group_reduce_max(uiVal);

	  if(uiMaxVal >= uiKey)
	    {
	      //check if the key is found
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
** bRemove:
** a work-group level function. searches for uiKey in the set. 
** if uiKey is found removes it. if not found returns false.
*/

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



__kernel void HTSTopKernel(__global void* pvOclReqQueue,
			   __global void* pvHashTable
			   __global void* pvNodePool,
			   uint  uiReqCount)
{
  uint uiFlags;

  //get the svm data structures
  TQueuedRequest* pOclReqQueue = (TQueuedRequest *)pvOclReqQueue;
  TLLNode*        pNodePool    = (TLLNode *)pvNodePool;
  uint*           pHashTable   = (uint *)pvHashTable;  
  
  uint gid = get_global_id(0);

  if (gid < uiReqCount)
    {
      uiFlags = pOclReqQueue[gid].uiFlags;
      uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
      pOclReqQueue[gid].uiFlags = uiFlags;
      pOclReqQueue[gid].pStatus = NULL;
    }

  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
}

