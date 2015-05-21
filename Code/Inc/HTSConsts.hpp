#ifndef _HTS_CONSTS_HPP_
#define _HTS_CONSTS_HPP_

#define  HTS_OK                            (1)
#define  HTS_NOT_OK                        (-1)

#define  THREAD_REQUEST_BUFFER_SIZE        (512)

#define  REQ_QUEUE_SIZE                    (1024)
#define  REQ_QUEUE_SIZE_MASK               (0x03FF)

#define  OCL_REQ_QUEUE_SIZE                (4096)
#define  OCL_NODE_POOL_SIZE                (1048576)
#define  OCL_HASH_TABLE_SIZE               (1024)
#define  OCL_HASH_TABLE_MASK               (0x3FF)
#define  OCL_WG_SIZE                       (256)
#define  EMPTY_KEY                         (0) 
  
#define  SET_FLAG(f,b)                     ((f) | (b))
#define  RESET_FLAG(f,b)                   ((f) & ~(b))
#define  GET_FLAG(f,b)                     ((f)&(b))

#define  GET_PTR(f)                        ((f)>> 1)
#define  SET_PTR(f)                        ((f)<< 1)
#define  GET_DBIT(f)                       ((f) & (uint)(0x01)) 
#define  SET_DBIT(f)                       ((f) | (uint)(0x01)) 
#define  RESET_DBIT(f)                     ((f) & (uint)(~0x01)) 

enum eReqFlags
  {
    HTS_REQ_FULL      = 0x01,
    HTS_REQ_QUEUED    = 0x02,
    HTS_REQ_SUBMITTED = 0x04,
    HTS_REQ_COMPLETED = 0x08,
    HTS_REQ_ABORTED   = 0x10,
    HTS_REQ_BLOCKING  = 0x20
  };

enum eReqType
  {
    HTS_REQ_TYPE_FIND   = 0x01,
    HTS_REQ_TYPE_ADD    = 0x01,
    HTS_REQ_TYPE_REMOVE = 0x01,
  };
#endif
