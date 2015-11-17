
#define _OCL_CODE_
#include "HTSShared.hpp"

/*
** uiAlloc:
** a thread level function, to get an empty node from node pool pointed by
** pNodePooHead. 
**
*/
uint uiAlloc(TLLNode* pNodePool, uint uiPoolHead)
{
  uint uiLLMNode, uiLLNode;
  bool bFoundNode = false;

  while(bFoundNode != true)
    {
      uiLLMNode = pNodePool[uiPoolHead].uiNext;
      uiLLNode  = GET_PTR(uiLLMNode);
      if(uiLLNode != 0)
	{
	  uint uiLLMNextNode = pNodePool[uiLLNode].uiNext;
	  atomic_uint* pChgPtr =
	    (atomic_uint *)(&(pNodePool[uiPoolHead].uiNext)); 
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

  if(uiLLNode)
    pNodePool[uiLLNode].uiNext = 0;
  
  return uiLLNode;
}

/*
** uiFree:
** a thread level function, to put a node uiLLNode back to the node pool 
** pointed by pNodePoolHead. 
**
*/
bool uiFree(TLLNode* pNodePool, uint uiPoolHead, uint uiLLNode)
{
  uint uiLLMNextNode, uiLLNextNode, uiLLMNode;
  
  bool bNodeFreed                 =  false;

  while(bNodeFreed != true)
    {
      uiLLMNextNode        = pNodePool[uiPoolHead].uiNext;
      uiLLNextNode         = GET_PTR(uiLLMNode);
      uiLLMNode            = SET_MPTR(uiLLNode,1);

      pNodePool[uiLLNode].uiNext      = uiLLMNextNode;
      
      atomic_uint* pChgPtr =
	(atomic_uint *)(&(pNodePool[uiPoolHead].uiNext));
			
      bNodeFreed = atomic_compare_exchange_strong
			(pChgPtr,
			 &uiLLMNextNode,
			 uiLLMNode);
    }

  return bNodeFreed;
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
** bFind:
** A work-group level function. The work-group invoking this finds a given
** key in the set. 
 */
bool bFind(uint uiKey, TLLNode* pHashTable)
{
  return true;
}

/*
** bAdd:
** A work-group level function. Adds a key to the set.
** returns true if successful. false is fails.
*/

bool bAdd(uint uiKey, TLLNode* pNodePool, uint uiPoolHead, uint* pLLNode)
{
  uint uiLLNode;
  uint lid = get_local_id(0);

  /* get a LLNode */
  if(lid == 0)
    {
      uiLLNode = uiAlloc(pNodePool, uiPoolHead);
    }
  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);
  uiLLNode = work_group_broadcast(uiLLNode,0);

  *pLLNode = uiLLNode;

  if(uiLLNode == 0)
    return false;
  
  return true;
}

/*
** bRemove:
** A work-group level function. Removes a key from the set.
** returns true if successful. false is fails.
*/

bool bRemove(uint uiKey, TLLNode* pNodePool, uint uiPoolHead, uint uiLLNode)
{
  bool bNodeFreed;
  uint lid = get_local_id(0);

  /* get a LLNode */
  if(lid == 0)
    {
      bNodeFreed = uiFree(pNodePool, uiPoolHead, uiLLNode);
    }
  
  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);
  bNodeFreed = work_group_broadcast(bNodeFreed,0);

  return bNodeFreed;
}

/*
** HTSTopKernel:
** Top level kernel. Each workgroup takes one request from pvOclReqQueue
** and executes it. 
*/

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
  TLLNode*        pHashTable   = (TLLNode *)pvNodePool;  
  TMiscData*      pMiscData    = (TMiscData*)pvMiscData;
  uint            uiPoolHead   = pMiscData->uiPoolHead;
  
  uint grid = get_group_id(0);
  uint lid  = get_local_id(0);
  
  if (grid < uiReqCount)
    {
      uiKey   = pOclReqQueue[grid].uiKey; 
      uiType  = pOclReqQueue[grid].uiType;
      uiFlags = pOclReqQueue[grid].uiFlags;
      
      uint uiNode,uiIndex;

      if(uiType == HTS_REQ_TYPE_FIND)
	{
	  //bReqStatus = false;
	  bReqStatus = bFind(uiKey,
	  		     pHashTable);
	}
      else if(uiType == HTS_REQ_TYPE_ADD)
	{
	  //bReqStatus = true;
	  bReqStatus = bAdd(uiKey,
	  		    pNodePool,
	  		    uiPoolHead,
	  		    &uiNode);
	}
      else if(uiType == HTS_REQ_TYPE_REMOVE)
	{
	  //bReqStatus = true;
	  uiNode      = pOclReqQueue[grid].uiStatus;
	  bReqStatus  = bRemove(uiKey,
			       pNodePool,
			       uiPoolHead,
			       uiNode);
	}
      
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      
      if(bReqStatus == true)
	uiIndex = 1;
      else
	uiIndex = 0;

      uiNode = SET_MPTR(uiNode,uiIndex);
      
      if(lid == 0)
	{
	  uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
	  pOclReqQueue[grid].uiFlags  = uiFlags;
	  pOclReqQueue[grid].uiStatus = uiNode;
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
    }
}



