#ifndef _HTS_CONSTS_HPP_
#define _HTS_CONSTS_HPP_

#define  HTS_OK                            (1)
#define  HTS_NOT_OK                        (-1)

#define  THREAD_REQUEST_BUFFER_SIZE        (512)

#define  REQ_QUEUE_SIZE                    (1024)
#define  REQ_QUEUE_SIZE_MASK               (0x03FF)

#define  OCL_REQ_QUEUE_SIZE                (4096)
#define  OCL_WG_SIZE                       (256)

#define  SET_FLAG(f,b)                     ((f) | (b))
#define  RESET_FLAG(f,b)                   ((f) & ~(b))
#define  GET_FLAG(f,b)                     ((f)&(b))

enum eReqFlags
  {
    HTS_REQ_FULL      = 0x01,
    HTS_REQ_QUEUED    = 0x02,
    HTS_REQ_SUBMITTED = 0x04,
    HTS_REQ_COMPLETED = 0x08,
    HTS_REQ_ABORTED   = 0x10,
    HTS_REQ_BLOCKING  = 0x20
  };

#endif
