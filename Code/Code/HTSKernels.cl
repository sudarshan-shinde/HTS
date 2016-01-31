
#define _OCL_CODE_
#include "HTSShared.hpp"

/***
 * uiAlloc :
 * Tries to acquire a node from the stack given by <pNodePool>, with head 
 * pointed by <uiHeadIndex>.
 * A work-item level function.
 * Returns the index of acquired node.
 ***/
uint uiAlloc(TLLNode* pNodePool, uint uiHeadIndex) 
{ 
  uint uiLLMNode  = 0 ; 
  int  uiLLNode   = 0 ; 
  uint uiFreeBit  = 0 ;
  bool bFoundNode = false;

  /* iterate until the work-item claims a node */
  while( bFoundNode != true )
    {     
      uiLLMNode = pNodePool[uiHeadIndex].uiNext; 
      uiLLNode  = GET_PTR(uiLLMNode);
    
      if(uiLLNode >= OCL_NODE_POOL_SIZE)
	return NULL ;
      
      uint uiLLMNextNode = pNodePool[uiLLNode].uiNext; 
      uint uiLLNextNode  = GET_PTR(uiLLMNextNode);
      uiFreeBit          = GET_FBIT(uiLLMNextNode) ;
      
      /* if the top node is free, try claiming it */ 
      if(uiFreeBit)
	{ 
	  atomic_uint* pChgPtr =
	    (atomic_uint *)(&(pNodePool[uiHeadIndex].uiNext));

	  bFoundNode = atomic_compare_exchange_strong(pChgPtr,
						      &uiLLMNode,
						      uiLLMNextNode); 
	} 
    }

  /* if the node is claimed successfully, initialize and return it */
  pNodePool[uiLLNode].uiNext = 0;
  for(uint i = 0; i < OCL_WG_SIZE; i++) 
    pNodePool[uiLLNode].pE[i] = 0;
  
  return uiLLNode; 
} 

/***
 * uiFree :
 * Frees a node indexed by <uiDelNode>, and puts it back to the stack 
 * <pNodePool>. <uiHeadIndex> points to the top of the stack.
 * Returns true if successful. 
 ***/

uint uiFree( TLLNode* pNodePool, uint uiHeadIndex, uint uiDelNode)
{ 
  uint uiLLMNode    = 0 ; 
  uint uiLLNode     = 0 ; 
  uint uiLLDelMNode = 0 ;
  uint uiLLNewNode  = 0 ;
  uint uiFreeBit    = 0 ;

  if(!uiDelNode)
    return HTS_FAILURE;
  
  /* check if free bit is set. if yes, this indicates attempt to 
     free already freed node */
  uiLLDelMNode = pNodePool[uiDelNode].uiNext;
  uiFreeBit    = GET_FBIT(uiLLDelMNode);
  if(uiFreeBit)
    return HTS_FAILURE;
  
  /* try to push the node to be freed to the top of the stack */
  bool bFreedNode   = false; 
  while( bFreedNode != true )
    { 
      uiLLMNode    = pNodePool[uiHeadIndex].uiNext ; 
      uiLLNode     = GET_PTR(uiLLMNode) ; 
      uiLLDelMNode = SET_FBIT(uiLLMNode); 
      
      pNodePool[uiDelNode].uiNext = uiLLDelMNode; 
      atomic_uint* pChgPtr =
	(atomic_uint *)(&(pNodePool[uiHeadIndex].uiNext));
      
      uiLLNewNode = SET_PTR(uiDelNode) ;
      
      bFreedNode = atomic_compare_exchange_strong(pChgPtr,
						  &uiLLMNode,
						  uiLLNewNode);
    }
  
  return HTS_SUCCESS;
} 

uint uiHashFunction(uint uiKey) 
{
    return uiKey & OCL_HASH_TABLE_MASK ;
}

/***
 * uiFindKeyIndex :
 * Given a key, finds its index in an array
 ***/
uint uiFindKeyIndex(uint* pKeys, uint uiInputKey)
{
  __local uint uiKeyIndex;
  uint uiLid = get_local_id(0);

  if(uiLid == PRINCIPAL_THREAD)
    uiKeyIndex = 0;
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
  
  if(pKeys[uiLid] == uiInputKey)
    uiKeyIndex = uiLid +1;
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  return uiKeyIndex;
}

/***
 * iWindow :
 * Given a key, finds a window in which the key is
 ***/
uint uiWindow(TLLNode*  pNodePool,
	      uint      uiInputKey,
	      uint      uiPrevRef,
	      uint      uiNextRef,
	      uint*     pKeyIndex)
{
  uint uiLid = get_local_id(0);

  /* initialize key index to NULL */
  *pKeyIndex = 0;

  /* get the next ref and check the bits*/
  uint uiMNRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiMNRef = pNodePool[uiPrevRef].uiNext;
    }
  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);
  uiMNRef = work_group_broadcast(uiMNRef, PRINCIPAL_THREAD);
  
  uint uiNRef    = GET_PTR(uiMNRef);
  uint uiPBits   = GET_BITS(uiMNRef);

  /* if the node is deleted or marked, return failure */  
  if(GET_FBIT(uiPBits) || GET_DBIT(uiPBits))
    return HTS_FAILURE;

  /* if next node is different, return failure */  
  if(uiNRef != uiNextRef)
    return HTS_FAILURE;

  /* if next node is NULL, return success */
  if(!uiNRef)
    return HTS_SUCCESS;

  uint uiMNNRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiMNNRef = pNodePool[uiNRef].uiNext;
    }
  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);
  uiMNNRef = work_group_broadcast(uiMNNRef, PRINCIPAL_THREAD);
  
  uint uiNNRef  = GET_PTR(uiMNNRef);
  uint uiNBits  = GET_BITS(uiMNNRef);

  if(GET_FBIT(uiNBits) || GET_DBIT(uiNBits))
    return HTS_FAILURE;

  /* find out if the input key is in the range */
  __local uint uiPrevKey[OCL_WG_SIZE];
  __local uint uiNextKey[OCL_WG_SIZE];
  
  uiPrevKey[uiLid] = pNodePool[uiPrevRef].pE[uiLid];  
  uiNextKey[uiLid] = pNodePool[uiNextRef].pE[uiLid];
  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);
  
  uint uiPrevMaxKey = work_group_reduce_max(uiPrevKey[uiLid]);
  uint uiNextMaxKey = work_group_reduce_max(uiNextKey[uiLid]);  

  /* DEBUG 
  return HTS_FAILURE;
   DEBUG */
  
  /* if we have crossed window for input key, return fatal error. this 
     should never happen */
  if(uiInputKey < uiPrevMaxKey)
    return HTS_FATAL_ERROR;

  /* if input key is not in the range, return failure */  
  int iStatus;  
  if(uiInputKey > uiNextMaxKey)
    {
      iStatus = HTS_FAILURE;
    }
  else
    {
      iStatus    = HTS_SUCCESS;
      *pKeyIndex = uiFindKeyIndex(uiNextKey,uiInputKey);
    }
  
  return iStatus;
}

/***
 * Debug function:
 ***/
uint uiDWindow(TLLNode*  pNodePool,
	       uint      uiInputKey,
	       uint      uiPrevRef,
	       uint      uiNextRef,
	       uint*     pKeyIndex)
{
  *pKeyIndex = 0;

  if(uiNextRef != 0)
    return HTS_FAILURE;

  return HTS_SUCCESS;
}

/*** 
 * uiFind:
 * Experimental.
 ***/
uint uiFind(TLLNode* pNodePool,
	    uint     uiNodeHead,
	    uint     uiInputKey,
	    uint*    pPrevRef,
	    uint*    pNextRef,	    
	    uint*    pKeyIndex)
{
  uint uiLid      = get_local_id(0);

  bool bFoundFlag = false;
  while(!bFoundFlag)
    {
      /* get the first node */
      uint uiPRef    = uiHashFunction(uiInputKey);
      
      uint uiMNRef, uiNRef;
      if(uiLid == PRINCIPAL_THREAD)
	uiMNRef      = pNodePool[uiPRef].uiNext;
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      uiMNRef        = work_group_broadcast(uiMNRef,PRINCIPAL_THREAD);
      
      uiNRef         = GET_PTR(uiMNRef);
      *pKeyIndex     = 0;
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

      uint uiStatus = HTS_FAILURE;
      while(uiStatus == HTS_FAILURE)
	{
	  uiStatus = uiWindow(pNodePool,uiInputKey,uiPRef,uiNRef,pKeyIndex);
	  //uiStatus = uiDWindow(pNodePool,uiInputKey,uiPRef,uiNRef,pKeyIndex); 
	  if(uiStatus == HTS_FAILURE)
	    {
	      uiPRef    = uiNRef;

	      if(uiLid == PRINCIPAL_THREAD)
		uiMNRef = pNodePool[uiPRef].uiNext;
	      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	      uiMNRef   = work_group_broadcast(uiMNRef,PRINCIPAL_THREAD);
	      
	      uiNRef    = GET_PTR(uiMNRef);
	    }
	  else
	    {
	      *pPrevRef = uiPRef;
	      *pNextRef = uiNRef;
	    }
	  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);
	}

      bFoundFlag = true;
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);      
    }

  return HTS_SUCCESS;    
}

/*** 
 * uiMinEmptySlot:
 * Experimental.
 ***/
uint uiMinEmptySlot(TLLNode* pNodePool, uint uiRef)
{
  uint uiLid = get_local_id(0);
  uint uiKey = pNodePool[uiRef].pE[uiLid];

  uint uiIndex = uiLid;
  if(uiKey != EMPTY_KEY)
    uiIndex = OCL_WG_SIZE;
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  uint uiMinIndex = work_group_reduce_min(uiIndex);
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  return uiMinIndex;
}

/*** 
 * uiCreate:
 * Experimental.
 ***/
uint uiCreateAndAdd(TLLNode* pNodePool,
		    uint     uiNodeHead,
		    uint     uiInputKey,
		    uint*    pNewRef)
{
  uint uiLid    = get_local_id(0);

  /* create a new node */
  uint uiNewRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiNewRef = uiAlloc(pNodePool, uiNodeHead);
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  /* broadcast new node to all work items */
  uiNewRef = work_group_broadcast(uiNewRef,PRINCIPAL_THREAD);  

  /* initialize and copy input key */
  pNodePool[uiNewRef].pE[uiLid] = 0;
  if(uiLid == PRINCIPAL_THREAD)
    {
      pNodePool[uiNewRef].pE[0]  = uiInputKey;
      pNodePool[uiNewRef].uiNext = 0;
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);      

  /* return new node */
  *pNewRef = uiNewRef;
  
  return HTS_SUCCESS;
}

/*** 
 * uiCopy:
 * Experimental.
 ***/
uint uiCopyAndAdd(TLLNode* pNodePool,
		  uint     uiNodeHead,
		  uint     uiOrigRef,
		  uint     uiInputKey,
		  uint     uiMinIndex,
		  uint*    pNewRef)
{
  uint uiLid    = get_local_id(0);
  
  /* create a new node */
  uint uiNewRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiNewRef = uiAlloc(pNodePool, uiNodeHead);
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  /* broadcast new node to all work items */
  uiNewRef = work_group_broadcast(uiNewRef,PRINCIPAL_THREAD);  

  /* copy and insert input key */
  pNodePool[uiNewRef].pE[uiLid] = pNodePool[uiOrigRef].pE[uiLid];
	  
  if(uiLid == PRINCIPAL_THREAD)
    {
      pNodePool[uiNewRef].pE[uiMinIndex] = uiInputKey;
      pNodePool[uiNewRef].uiNext         = pNodePool[uiOrigRef].uiNext;  
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  *pNewRef = uiNewRef;
  
  return HTS_SUCCESS;
}

uint uiSplitCopyAndAdd(TLLNode* pNodePool,
		       uint     uiNodeHead,
		       uint     uiOrigRef,
		       uint     uiInputKey,
		       uint*    pNewRef,
		       uint*    pNewNextRef)
{
  uint uiLid    = get_local_id(0);

  /* allocate ane link two nodes */
  uint uiNewRef, uiNewNextRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiNewRef     = uiAlloc(pNodePool, uiNodeHead);
      uiNewNextRef = uiAlloc(pNodePool, uiNodeHead);

      pNodePool[uiNewRef].uiNext = SET_PTR(uiNewNextRef);
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  /* broadcast new nodes to rest of the work items */
  uiNewRef     = work_group_broadcast(uiNewRef,PRINCIPAL_THREAD);
  uiNewNextRef = work_group_broadcast(uiNewNextRef,PRINCIPAL_THREAD);  

  /* copy */
  pNodePool[uiNewRef].pE[uiLid]     = 0;
  pNodePool[uiNewNextRef].pE[uiLid] = 0;
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
  
  uint uiKey = pNodePool[uiOrigRef].pE[uiLid];
  
  if(uiKey < uiInputKey)
    {
      pNodePool[uiNewRef].pE[uiLid]     = uiKey;	      
    }
  else
    {
      pNodePool[uiNewNextRef].pE[uiLid] = uiKey;	      	      
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
  
  /* insert key */
  uint uiMinIndex = uiMinEmptySlot(pNodePool,uiNewRef);
  if(uiLid == PRINCIPAL_THREAD)
    {
      pNodePool[uiNewRef].pE[uiMinIndex] = uiInputKey;
      pNodePool[uiNewNextRef].uiNext     = pNodePool[uiOrigRef].uiNext;  
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
  
  *pNewRef     = uiNewRef;
  *pNewNextRef = uiNewNextRef;
  
  return HTS_SUCCESS;
}
  
/*** 
 * uiClone:
 * Experimental.
 ***/
uint uiCloneAndAdd(TLLNode* pNodePool,
		   uint     uiNodeHead,
		   uint     uiNRef,
		   uint     uiInputKey,
		   uint*    pNewRef,
		   uint*    pNewNextRef)
{
  uint uiLid      = get_local_id(0);

  /* initialize new nodes to NULL */
  *pNewRef        = 0;
  *pNewNextRef    = 0;
  
  /* get the minimum empty slot */
  //uint uiMNRef    = pNodePool[uiPrevRef].uiNext;
  //uint uiNRef     = GET_PTR(uiMNRef);
  //work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);        

  /* if next node is NULL, create a new node */
  if(!uiNRef)
    {
      uint uiStatus = uiCreateAndAdd(pNodePool,
				     uiNodeHead,
				     uiInputKey,
				     pNewRef);
      return uiStatus;
    }

  /* check if a slot is empty in the next node */
  uint uiMinIndex = uiMinEmptySlot(pNodePool,uiNRef);

  /* if a slot is found, copy and insert input key */
  if(uiMinIndex != OCL_WG_SIZE)
    {
      uint uiStatus = uiCopyAndAdd(pNodePool,
				   uiNodeHead,
				   uiNRef,
				   uiInputKey,
				   uiMinIndex,
				   pNewRef);

      return uiStatus;
    }

  /* if no slot is found split the original node into two */
  uint uiStatus = uiSplitCopyAndAdd(pNodePool,
				    uiNodeHead,
				    uiNRef,
				    uiInputKey,
				    pNewRef,
				    pNewNextRef);
  return uiStatus;
}

/*** 
 * uiFindLastKey:
 * Experimental.
 ***/
uint uiFindLastKey(TLLNode* pNodePool, uint uiNRef)
{
  uint uiLid  = get_local_id(0);
  uint uiKey  = pNodePool[uiNRef].pE[uiLid];
  uint uiFlag = (uiKey != EMPTY_KEY)? 1:0;
  work_group_barrier(CLK_LOCAL_MEM_FENCE|CLK_GLOBAL_MEM_FENCE);

  uint uiNonEmptyKeys = work_group_reduce_add(uiFlag);

  if(uiNonEmptyKeys > 1)
    return HTS_FALSE;

  return HTS_TRUE;
}

/*** 
 * uiCopy:
 * Experimental.
 ***/
uint uiCopyAndRemove(TLLNode* pNodePool,
		     uint     uiNodeHead,
		     uint     uiOrigRef,
		     uint     uiKeyIndex,
		     uint*    pNewRef)
{
  uint uiLid    = get_local_id(0);
  
  /* create a new node */
  uint uiNewRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiNewRef = uiAlloc(pNodePool, uiNodeHead);
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  /* broadcast new node to all work items */
  uiNewRef = work_group_broadcast(uiNewRef,PRINCIPAL_THREAD);  

  /* copy and remove key */
  pNodePool[uiNewRef].pE[uiLid] = pNodePool[uiOrigRef].pE[uiLid];
	  
  if(uiLid == PRINCIPAL_THREAD)
    {
      pNodePool[uiNewRef].pE[uiKeyIndex -1] = EMPTY_KEY;
      pNodePool[uiNewRef].uiNext            = pNodePool[uiOrigRef].uiNext;  
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

  *pNewRef = uiNewRef;
  
  return HTS_SUCCESS;
}

/*** 
 * uiClone:
 * Experimental.
 ***/
uint uiCloneAndRemove(TLLNode* pNodePool,
		      uint     uiNodeHead,
		      uint     uiNRef,
		      uint     uiKeyIndex,
		      uint*    pNewRef)
{
  uint uiLid      = get_local_id(0);

  /* initialize new nodes to NULL */
  *pNewRef        = 0;

  uint uiMNNRef,uiNNRef;
  if(uiLid == PRINCIPAL_THREAD)
    {
      uiMNNRef   = pNodePool[uiNRef].uiNext;
    }
  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
  uiMNNRef   = work_group_broadcast(uiMNNRef, PRINCIPAL_THREAD);
  uiNNRef    = GET_PTR(uiMNNRef);

  /* check if it is the last key left in the node */
  uint uiStatus = uiFindLastKey(pNodePool,uiNRef);
  if(uiStatus == HTS_TRUE)
    {
      *pNewRef = uiNNRef;
      return HTS_SUCCESS;
    }
  
  uiStatus = uiCopyAndRemove(pNodePool,
			     uiNodeHead,
			     uiNRef,
			     uiKeyIndex,
			     pNewRef);

  return uiStatus;
}

/*** 
 * uiRetainRef:
 * Experimental.
 ***/
uint uiRetainRef(TLLNode* pNodePool, uint uiRef)
{
  if(!uiRef)
    return HTS_SUCCESS;
  
  uint uiMNNRef  = pNodePool[uiRef].uiNext;
  uint uiMRNNRef = SET_RBIT(uiMNNRef);
  
  atomic_uint* pChgPtr =
    (atomic_uint *)(&(pNodePool[uiRef].uiNext));
  
  bool bRetainFlag;
  bRetainFlag = atomic_compare_exchange_strong(pChgPtr,
					       &uiMNNRef,
					       uiMRNNRef);

  if(!bRetainFlag)
    return HTS_FAILURE;

  return HTS_SUCCESS;
}

/*** 
 * uiReleaseRef:
 * Experimental.
 ***/
uint uiReleaseRef(TLLNode* pNodePool, uint uiRef)
{
  if(!uiRef)
    return HTS_SUCCESS;

  uint uiMRNNRef  = pNodePool[uiRef].uiNext;
  uint uiMNNRef   = RESET_RBIT(uiMNNRef);
  
  atomic_uint* pChgPtr =
    (atomic_uint *)(&(pNodePool[uiRef].uiNext));
  
  bool bReleaseFlag;
  bReleaseFlag = atomic_compare_exchange_strong(pChgPtr,
						&uiMRNNRef,
						uiMNNRef);

  if(!bReleaseFlag)
    return HTS_FAILURE;

  return HTS_SUCCESS;
}

/*** 
 * uiAdd:
 * Experimental.
 ***/
uint uiAdd(TLLNode* pNodePool, uint uiNodeHead, uint uiInputKey)
{
  uint uiLid      = get_local_id(0);
  uint uiStatus   = HTS_SUCCESS;

  /* search the key in the set. if found return failure to add */
  uint uiPrevRef  = 0;
  uint uiNextRef  = 0;
  uint uiKeyIndex = 0;
  bool bDoneFlag  = false;

  while(bDoneFlag == false)
    {
      uiStatus   = uiFind(pNodePool,
			  uiNodeHead,
			  uiInputKey,
			  &uiPrevRef,
			  &uiNextRef,
			  &uiKeyIndex);
      if(uiStatus == HTS_SUCCESS)
	{
	  if(uiKeyIndex)
	    return HTS_FAILURE;
	}
      else
	{
	  return uiStatus;
	}

      uint uiMNRef,uiNRef,uiRBit;
      if(uiLid == PRINCIPAL_THREAD)
	{
	  uiMNRef   = pNodePool[uiPrevRef].uiNext;
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      
      uiMNRef   = work_group_broadcast(uiMNRef, PRINCIPAL_THREAD);
      uiNRef    = GET_PTR(uiMNRef);
      uiRBit    = GET_RBIT(uiMNRef);
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      
      if(!uiRBit)
	{
	  /* lock the pointer */
	  uint uiRetainFlag;
	  if(uiLid == PRINCIPAL_THREAD)
	    {
	      uiRetainFlag = uiRetainRef(pNodePool, uiNRef);
	    }
	  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	  uiRetainFlag   = work_group_broadcast(uiRetainFlag, PRINCIPAL_THREAD);

	  if(uiRetainFlag == HTS_SUCCESS)
	    {
	      /* prepare a clone */
	      uint uiNewRef, uiNewNextRef;
	      uiStatus      = uiCloneAndAdd(pNodePool,
					    uiNodeHead,
					    uiNRef,
					    uiInputKey,
					    &uiNewRef,
					    &uiNewNextRef);
	      
	      if(uiStatus == HTS_FAILURE)
		return HTS_FAILURE;

	      /* DEBUG 
		 return HTS_SUCCESS;
		 DEBUG */
	  
	      /* try to change node from its clone */
	      if(uiLid == PRINCIPAL_THREAD)
		{
		  uint uiMNewRef   = SET_PTR(uiNewRef);

		  atomic_uint* pChgPtr =
		    (atomic_uint *)(&(pNodePool[uiPrevRef].uiNext));
		  
		  bDoneFlag = atomic_compare_exchange_strong(pChgPtr,
							     &uiMNRef,
							     uiMNewRef);
		  if(!bDoneFlag)
		    {
		      uiFree(pNodePool,uiNodeHead,uiNewRef);
		      uiFree(pNodePool,uiNodeHead,uiNewNextRef);
		    }
		  else
		    {
		      uiFree(pNodePool,uiNodeHead,uiNRef);
		    }
		}
	      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	      bDoneFlag = work_group_broadcast(bDoneFlag, PRINCIPAL_THREAD);
	    }
	}
      else
	{
	  return HTS_ATTEMPT_FAILED;
	}
    }
  
  return uiStatus;
}

/*** 
 * uiRemove:
 * Experimental.
 ***/
uint uiRemove(TLLNode* pNodePool, uint uiNodeHead, uint uiInputKey)
{
  uint uiLid      = get_local_id(0);
  uint uiStatus   = HTS_SUCCESS;

  /* search the key in the set. if not found return failure to delete */
  uint uiPrevRef  = 0;
  uint uiNextRef  = 0;
  uint uiKeyIndex = 0;
  uint bDoneFlag  = false;

  while(bDoneFlag == false)
    {
      uiStatus   = uiFind(pNodePool,
			  uiNodeHead,
			  uiInputKey,
			  &uiPrevRef,
			  &uiNextRef,
			  &uiKeyIndex);
      if(uiStatus == HTS_FAILURE)
	{
	  return HTS_FAILURE;
	}
      else
	{
	  if(!uiKeyIndex)
	    return HTS_FAILURE;
	}

      uint uiMNRef,uiNRef,uiRBit;
      if(uiLid == PRINCIPAL_THREAD)
	{
	  uiMNRef   = pNodePool[uiPrevRef].uiNext;
	}
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      uiMNRef   = work_group_broadcast(uiMNRef, PRINCIPAL_THREAD);
      uiNRef    = GET_PTR(uiMNRef);
      uiRBit    = GET_RBIT(uiMNRef);
      
      if(!uiRBit)
	{
	  /* lock the pointer */
	  uint uiRetainFlag;
	  if(uiLid == PRINCIPAL_THREAD)
	    {
	      uiRetainFlag = uiRetainRef(pNodePool, uiNRef);
	    }
	  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	  uiRetainFlag   = work_group_broadcast(uiRetainFlag, PRINCIPAL_THREAD);

	  if(uiRetainFlag == HTS_SUCCESS)
	    {
	      /* prepare a clone */
	      uint uiNewRef;
	      uiStatus      = uiCloneAndRemove(pNodePool,
					       uiNodeHead,
					       uiNRef,
					       uiKeyIndex,
					       &uiNewRef);
	      
	      if(uiStatus == HTS_FAILURE)
		return HTS_FAILURE;
	      
	      /* DEBUG 
		 return HTS_SUCCESS;
		 DEBUG */
	      
	      /* try to change node from its clone */
	      if(uiLid == PRINCIPAL_THREAD)
		{
		  uint uiMNewRef   = SET_PTR(uiNewRef);
		  
		  atomic_uint* pChgPtr =
		    (atomic_uint *)(&(pNodePool[uiPrevRef].uiNext));
		  
		  bDoneFlag = atomic_compare_exchange_strong(pChgPtr,
							     &uiMNRef,
							     uiMNewRef);
		  if(!bDoneFlag)
		    {
		      uiFree(pNodePool,uiNodeHead,uiNewRef);
		    }
		  else
		    {
		      uiFree(pNodePool,uiNodeHead,uiNRef);
		    }
		}
	      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	      bDoneFlag = work_group_broadcast(bDoneFlag, PRINCIPAL_THREAD);
	    }
	}
      else
	{
	  return HTS_ATTEMPT_FAILED;	  
	}
    }
  return uiStatus;
}

/*** 
 * HTSTopKernel:
 * Reads <uiReqCount> requests from the queue <pvOclReqQueue>. Each work
 * group processes one request, with <pvNodePool> as a pool of nodes
 * being used in the set. <pvMiscData> contains the top node of the 
 * <pvNodePool>.
 ***/

__kernel void HTSTopKernel(__global void* pvOclReqQueue,
                           __global void* pvNodePool,
                           __global void* pvMiscData,
                           uint           uiReqCount)
{
  uint uiFlags     = 0 ;
  uint uiKey       = 0 ;
  uint uiStatus    = 0 ;
  uint uiType      = 0 ;
  uint uiReqStatus = 0 ;
  
  //get the svm data structures
  TQueuedRequest* pOclReqQueue = (TQueuedRequest *)pvOclReqQueue;
  TLLNode*        pNodePool    = (TLLNode *)pvNodePool; 
  TMiscData*      pMiscData    = (TMiscData*)pvMiscData;
  uint            uiHeadIndex  = pMiscData->uiHeadIndex; 
  
  uint uiGrid = get_group_id(0);
  uint uiLid  = get_local_id(0);
  
  if (uiGrid < uiReqCount)
    {
      uiKey   = pOclReqQueue[uiGrid].uiKey; 
      uiType  = pOclReqQueue[uiGrid].uiType;
      uiFlags = pOclReqQueue[uiGrid].uiFlags;
      
      if(uiType == HTS_REQ_TYPE_FIND) 
	{
	  uint uiPRef, uiNRef, uiIndex;
	  uiReqStatus = uiFind(pNodePool,
			       uiHeadIndex,
			       uiKey,
			       &uiPRef,
			       &uiNRef,
			       &uiIndex);
	  if(uiIndex != 0)
	    uiReqStatus = HTS_SUCCESS;
	  else
	    uiReqStatus = HTS_FAILURE;
	}
      else if(uiType == HTS_REQ_TYPE_ADD)
	{
	  uiReqStatus = uiAdd(pNodePool,uiHeadIndex,uiKey);
	}
      else if(uiType == HTS_REQ_TYPE_REMOVE)
	{
	  uiReqStatus = uiRemove(pNodePool,uiHeadIndex,uiKey);
	}
      
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
      
      if(uiLid == PRINCIPAL_THREAD)
	{
	  uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
	  pOclReqQueue[uiGrid].uiFlags  = uiFlags;
	  pOclReqQueue[uiGrid].uiStatus = uiReqStatus;
	}
      
      work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
    } 
}



