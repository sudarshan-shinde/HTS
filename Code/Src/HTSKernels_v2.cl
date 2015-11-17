#define _OCL_CODE_
#include "HTSShared.hpp"

# pragma OPENCL EXTENSION cl_amd_printf:enable
//#define START_INDEX		OCL_HASH_TABLE_SIZE 

/* Function name: ALLOC
* Arguments:	TLLNode *pNodePool (pointer to nodepool)	
* Return value: index of a free node in nodepool
* Description: This function returns index of a free node, whose freebit is 1 (3rd bit) 
*/
uint uiAlloc( TLLNode *pNodePool, uint uiReadIndex) { // --> DONE

	uint uiLLMNode = 0 ; /* [<next-node-index>,<Bits(f,r,m)>] */
	uint uiLLNode = 0 ; /* next-node-index in nodepool, shift 3 bits right to get */ 
	bool bFoundNode =  false  ; /* true, node found otherwise not found */
	uint freeBit = 0 ;

	while( bFoundNode != true ) { /* iterate untill NodeFound */

		uiLLMNode = pNodePool[uiReadIndex].uiNext ; /* Always top node is free : stack */
		uiLLNode = GET_PTR(uiLLMNode) ;/* Get actual index of next node in pool */	

		uint uiLLMNextNode = pNodePool[uiLLNode].uiNext ; /* Get next node index */
		uint uiLLNextNode = GET_PTR(uiLLMNextNode) ;
		freeBit = GET_FBIT(uiLLMNextNode) ; /* Get free Bit */

		if(freeBit) { /* If, this is a free node */					
			atomic_uint* pChgPtr =
				(atomic_uint *)(&(pNodePool[uiReadIndex].uiNext));
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
void uiFree( TLLNode *pNodePool,uint uiWriteIndex, uint iDelNode ) {  // --> DONE

	uint uiLLMNode = 0 ; /* [<next-node-index>,<Bits(f,r,m)>] */
	uint uiLLNode = 0 ; /* next-node-index in nodepool, shift 3 bits right to get */ 
	bool bFoundNode =  false  ; /* true, node found otherwise not found */
	uint uiLLDelMNode = 0 ;
	uint uiLLNewNode = 0 ;

	while( bFoundNode != true ) { /* iterate untill NodeFound */

		uiLLMNode = pNodePool[uiWriteIndex].uiNext ; /* Always top node is free : stack */
		uiLLNode = GET_PTR(uiLLMNode) ; /* Get actual index of next node in pool */
		uiLLDelMNode = SET_FBIT(uiLLMNode); /* index with free bit set */

		pNodePool[iDelNode].uiNext = uiLLDelMNode; // points to first node

		atomic_uint* pChgPtr =
			(atomic_uint *)(&(pNodePool[uiWriteIndex].uiNext));

		uiLLNewNode = SET_PTR(iDelNode) ;

		bFoundNode = atomic_compare_exchange_strong
			(pChgPtr,
			&uiLLMNode,
			uiLLNewNode);
		} // end-of-while-loop
	} // end-of-free

/*
** uiHashFunction:
** hash function to map key to hash table index.
** 
**
*/
uint uiHashFunction(uint uiKey) // --> DONE
	{
	return uiKey & OCL_HASH_TABLE_MASK ;
	}

/** bDeleteMakredNodes:
** thread level function
** deletes all the makred nodes next to uiPPtr
** 
**
*/
bool bDelMarkedNodes(uint uiPPtr, TLLNode* pNodePool, uint uiWriteIndex) // --> DONE
	{
	uint uiCMPtr, uiCPtr, uiPBit;
	uint uiNMPtr, uiNPtr, uiCBit;
	uint uiNewCMPtr;
	bool bCASStatus = false;

	//TLLNode* pNodePoolHead = pNodePool + OCL_HASH_TABLE_SIZE;

	//remove all marked nodes after uiPPtr
	bool bAllMarkedDeleted = false;
	while(bAllMarkedDeleted != true)
		{
		uiCMPtr  = pNodePool[uiPPtr].uiNext;
		uiCPtr   = GET_PTR(uiCMPtr);
		uiPBit   = GET_DBIT(uiCMPtr);

		if((uiCPtr != 0) && (uiPBit == 1)) // If not marked for deletion
			{
			uiNMPtr  = pNodePool[uiCPtr].uiNext; // move to next pointer
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
** returns true if uiKey is found.
*/

bool bFind(uint      uiKey,
		   TLLNode*  pNodePool,
		   uint      uiWriteIndex,
		   uint*     pNode,
		   uint*     pIndex)	// --> DONE
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
		if((uiCPtr != 0) && (uiPBit == 0)) // if not marked for deletion
			{
			uint uiVal    = pNodePool[uiCPtr].pE[lid];
			uint uiMaxVal = work_group_reduce_max(uiVal); // finds maximum value in WG

			if(uiMaxVal >= uiKey)
				{
				// check if the key is found
				uint uiIndex = 0 ;
				if(uiKey == uiVal)
					uiIndex = lid + 1;
				else
					uiIndex = 0;

				uiIndex = work_group_reduce_max(uiIndex);

				*pNode     = uiPPtr; // this is list-node
				*pIndex    = uiIndex; // index among 256

				if(uiIndex)
					bKeyFound = true;

				bNodeFound = true;
				}
			else 
				{
				uiPPtr = uiCPtr; // go to next node in node pool
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
	//find the node after with the key is supposed to go
	bFoundKey = bFind(uiKey, pNodePool, uiWriteIndex, &uiPPtr, &uiIndex); //uiIndex = 0 ,incase key not found

	work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
	if(bFoundKey == true) 
		return false;

	// proceed to add
	uint uiCMPtr = pNodePool[uiPPtr].uiNext;
	uint uiCPtr  = GET_PTR(uiCMPtr);
	uint uiPBit  = GET_DBIT(uiCMPtr);

	if (uiPBit == 0) // I, think this will always be ZERO for this node
		{
		if(uiCPtr != 0)
			{
			// check for an empty slot
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
			uint uiNewPtr = 0;
			uint uiNewMPtr = 0;
			if(lid == 0)
				{				
				uiNewPtr  = uiAlloc(pNodePool,uiReadIndex);
				uiNewMPtr = SET_PTR(uiNewPtr);
				}
			work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
			uiNewPtr  = work_group_broadcast(uiNewPtr,0);
			uiNewMPtr = work_group_broadcast(uiNewMPtr,0); // WT0 updating bAddedKey value	  
			pNodePool[uiNewPtr].pE[lid] = EMPTY_KEY;

			if(lid == 0)
				{
				pNodePool[uiNewPtr].pE[0] = uiKey;

				atomic_uint* pChgPtr =
					(atomic_uint *)(&(pNodePool[uiPPtr].uiNext));

				bAddedKey = atomic_compare_exchange_strong
					(pChgPtr,
					&uiCMPtr, 
					uiNewMPtr); // Attaching list atomically
				}
			work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
			bAddedKey = work_group_broadcast(bAddedKey,0); // WT0 updating bAddedKey value
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
		if(lid == uiIndex -1) // index in a node where key exists
			{
			uiVal = pNodePool[uiCPtr].pE[lid];
			if(uiVal == uiKey)//  got key ???, remove it
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
	uint uiFlags = 0 ;
	uint uiKey = 0 ;
	uint uiStatus = 0 ;
	uint uiType = 0 ;
	bool bReqStatus = false ;

	//get the svm data structures
	TQueuedRequest* pOclReqQueue = (TQueuedRequest *)pvOclReqQueue ;
	TLLNode*        pNodePool    = (TLLNode *)pvNodePool ;
	//TLLNode*        pHashTable   = (TLLNode *)pvHashTable;  
	TMiscData*      pMiscData    = (TMiscData*)pvMiscData ;
	uint            uiReadIndex  = pMiscData->uiReadIndex ; 
	// uint            uiWriteIndex = pMiscData->uiWriteIndex ; --> original  
	uint            uiWriteIndex =  pMiscData->uiReadIndex; // Nipuna : 12-Nov-15

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

		uint uiNode = 0,uiIndex = 0;

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



