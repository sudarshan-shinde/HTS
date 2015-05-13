
#define _OCL_CODE_
#include "HTSShared.hpp"

__kernel void HTSTopKernel(__global void* pSVMBuf,
			   uint  uiReqCount)
{
  uint uiFlags;

  uint gid = get_global_id(0);

  if (gid < uiReqCount)
    {
      TQueuedRequest* pOclReqQueue = (TQueuedRequest *)pSVMBuf;

      uiFlags = pOclReqQueue[gid].uiFlags;
      uiFlags = SET_FLAG(uiFlags,HTS_REQ_COMPLETED);
      pOclReqQueue[gid].uiFlags = uiFlags;
      pOclReqQueue[gid].pStatus = NULL;
    }

  work_group_barrier(CLK_GLOBAL_MEM_FENCE|CLK_LOCAL_MEM_FENCE);
}

//__kernel HTSTopKernel()
//{
//}
