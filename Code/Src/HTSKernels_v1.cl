#define _OCL_CODE_
#include "HTSShared.hpp"

# pragma OPENCL EXTENSION cl_amd_printf:enable


/* Function name: ALLOC
* Arguments:	TLLNode *pNodePool (pointer to nodepool)	
* Return value: index of a free node in nodepool
* Description: This function returns index of a free node, whose freebit is 1 (3rd bit) 
*/
uint uiAlloc( TLLNode *pNodePool, uint uiHeadIndex) { // --> DONE

	uint uiLLMNode = 0 ; /* [<next-node-index>,<Bits(f,r,m)>] */
	uint uiLLNode = 0 ; /* next-node-index in nodepool, shift 3 bits right to get */ 
	bool bFoundNode =  false  ; /* true, node found otherwise not found */
	uint freeBit = 0 ;

	while( bFoundNode != true ) { /* iterate untill NodeFound */

		uiLLMNode = pNodePool[uiHeadIndex].uiNext ; /* Always top node is free : stack */
		uiLLNode = GET_PTR(uiLLMNode) ;/* Get actual index of next node in pool */	

		uint uiLLMNextNode = pNodePool[uiLLNode].uiNext ; /* Get next node index */
		uint uiLLNextNode = GET_PTR(uiLLMNextNode) ;
		freeBit = GET_FBIT(uiLLMNextNode) ; /* Get free Bit */

		if(freeBit) { /* If, this is a free node */					
			atomic_uint* pChgPtr =
				(atomic_uint *)(&(pNodePool[uiHeadIndex].uiNext));
			// update starting index
			bFoundNode = atomic_compare_exchange_strong
				(pChgPtr,
				&uiLLMNode,
				uiLLMNextNode); // POINTS TO NEXT FREE NODE
			} // end-of-if
		} // end-of-while
	pNodePool[uiLLNode].uiNext = 0 ;
	return uiLLNode ; 
	} // end-of-alloc


/* Function name: Free()
* Arguments:	TLLNode *pNodePool (pointer to nodepool), Node index to be deleted	
* Return value: void
* Description: This function marks given index node as free node, by setting free bit
*/
bool uiFree( TLLNode *pNodePool,uint uiHeadIndex, uint iDelNode ) {  // --> DONE

	uint uiLLMNode = 0 ; /* [<next-node-index>,<Bits(f,r,m)>] */
	uint uiLLNode = 0 ; /* next-node-index in nodepool, shift 3 bits right to get */ 
	bool bFoundNode =  false  ; /* true, node found otherwise not found */
	uint uiLLDelMNode = 0 ;
	uint uiLLNewNode = 0 ;

	while( bFoundNode != true ) { /* iterate untill NodeFound */

		uiLLMNode = pNodePool[uiHeadIndex].uiNext ; /* Always top node is free : stack */
		uiLLNode = GET_PTR(uiLLMNode) ; /* Get actual index of next node in pool */
		uiLLDelMNode = SET_FBIT(uiLLMNode); /* index with free bit set */

		pNodePool[iDelNode].uiNext = uiLLDelMNode; // points to first node

		atomic_uint* pChgPtr =
			(atomic_uint *)(&(pNodePool[uiHeadIndex].uiNext));

		uiLLNewNode = SET_PTR(iDelNode) ;

		bFoundNode = atomic_compare_exchange_strong
			(pChgPtr,
			&uiLLMNode,
			uiLLNewNode);
		} // end-of-while-loop
		return bFoundNode ;
	} // end-of-free

/*
** uiHashFunction:
** hash function to map key to hash table index.
*/
uint uiHashFunction(uint uiKey) // --> DONE
	{
	return uiKey & OCL_HASH_TABLE_MASK ;
	}

/*
** bFind:
** a work-group level function. searches for uiKey in the set. 
** returns a node pNode such that next node's maximum key >= uiKey.
** also returns index in pIndex if the key is found.
** returns true if uiKey is found.
*/

bool bFind(uint      uiKey,
		   TLLNode*  pNodePool,
		   uint      uiHeadIndex,
		   uint*     pNode,
		   uint*     pIndex)	// --> DONE
	{
	return true;
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
		  uint      uiHeadIndex,
		  uint      *uiPPtr)
	{
	uint lid = get_local_id(0);

	//get a node allocated
	uint uiNewPtr = 0;
	uint uiNewMPtr = 0;
	if(lid == 0)
		{				
		uiNewPtr  = uiAlloc(pNodePool,uiHeadIndex);
		uiNewMPtr = SET_PTR(uiNewPtr);
		}
	work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	uiNewPtr  = work_group_broadcast(uiNewPtr,0);
	uiNewMPtr = work_group_broadcast(uiNewMPtr,0); 
	*uiPPtr = uiNewPtr ;
	if(uiNewPtr == 0) return false ; 	  
	return true;
	}

/*
** bRemove:
** Remove a node and mark it as free in NodePool
*/
bool bRemove(uint      uiKey,
			 TLLNode*  pNodePool,
			 uint      uiHeadIndex,
			 uint      uiDelNode)
	{
	//find the key

	bool bNodeFree =  false;

	uint lid = get_local_id(0);
	if(lid == 0) {
		bNodeFree = uiFree(pNodePool, uiHeadIndex, uiDelNode) ;
		}
	work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	bNodeFree  = work_group_broadcast(bNodeFree,0);

	return bNodeFree;
	}
// kernel calling from host
__kernel void HTSTopKernel(__global void* pvOclReqQueue,
						   __global void* pvNodePool,
						   __global void* pvMiscData,
						   uint  uiReqCount)
	{
	uint uiFlags = 0 ;
	uint uiKey = 0 ;
	uint uiStatus = 0 ;
	uint uiType = 0 ;
	bool bReqStatus = false ;
	
	//get the svm data structures
	TQueuedRequest* pOclReqQueue = (TQueuedRequest *)pvOclReqQueue ;
	TLLNode*        pNodePool    = (TLLNode *)pvNodePool ; // hash table + node pool
	TMiscData*      pMiscData    = (TMiscData*)pvMiscData ;
	uint            uiHeadIndex =  pMiscData->uiHeadIndex; // points to head of pool

	uint grid = get_group_id(0);
	uint lid  = get_local_id(0);

	if (grid < uiReqCount)
		{
		uiKey   = pOclReqQueue[grid].uiKey; 
		uiType  = pOclReqQueue[grid].uiType;
		uiFlags = pOclReqQueue[grid].uiFlags;

		uint uiNode ,uiIndex;

		if(uiType == HTS_REQ_TYPE_FIND) // Not implemented
			{
			bReqStatus = bFind(uiKey,
				pNodePool,
				uiHeadIndex,
				&uiNode,
				&uiIndex);
			}
		else if(uiType == HTS_REQ_TYPE_ADD)
			{
			bReqStatus = bAdd(uiKey,
				pNodePool,
				uiHeadIndex,
				&uiNode
				);
			}
		else if(uiType == HTS_REQ_TYPE_REMOVE)
			{
			uiNode = pOclReqQueue[grid].uiNode ; // for testing purpose : TODO - remove later
			work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
			bReqStatus = bRemove(uiKey,
				pNodePool,
				uiHeadIndex,
				uiNode);
			}

		work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

		if(bReqStatus == true)
			uiIndex = 1;
		else
			uiIndex = 0;

		if(lid == 0)
			{
			printf("%d",uiNode) ;
			uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
			pOclReqQueue[grid].uiFlags  = uiFlags;
			pOclReqQueue[grid].uiStatus = uiIndex;
			pOclReqQueue[grid].uiNode = uiNode ; // for testing purpose : TODO - remove later
			}
		work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);

		} 
	}



