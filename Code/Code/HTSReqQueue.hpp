
#pragma once

#include <windows.h>
#include "HTSConsts.hpp"
#include "HTSBasics.hpp"
#include "HTSShared.hpp"

class CRequestQueue
{
public:
  CRequestQueue();
  ~CRequestQueue();

  LONG uiPut(TQueuedRequest* pReq);
  LONG uiGet(TQueuedRequest* pReq);

private:
  TQueuedRequest  pReqQueue[REQ_QUEUE_SIZE];
  LONG            uiReadIndex;
  LONG            uiWriteIndex;
};

