#ifndef _HTS_CONSTS_HPP_
#define _HTS_CONSTS_HPP_


#define  HTS_OK                            (0)
#define  HTS_NOT_OK                        (1)

#define  HTS_TRUE                          (1)
#define  HTS_FALSE                         (0)

#define  THREAD_REQUEST_BUFFER_SIZE        (512)

#define  REQ_QUEUE_SIZE                    (1024)
#define  REQ_QUEUE_SIZE_MASK               (0x03FF)

#define  OCL_REQ_QUEUE_SIZE                (4096)
#define  OCL_NODE_POOL_SIZE                (1048576)
//#define  OCL_HASH_TABLE_SIZE               (1024)
//#define  OCL_HASH_TABLE_MASK               (0x3FF)
#define  OCL_HASH_TABLE_SIZE               (2)
#define  OCL_HASH_TABLE_MASK               (0x01)

#define  OCL_WG_SIZE                       (256)
#define  EMPTY_KEY                         (0) 
#define  PRINCIPAL_THREAD                  (0)
  
#define  FBIT                              (0X04)
#define  RBIT                              (0X02)
#define  DBIT                              (0X01)
  
#define  SET_FLAG(f,b)                     ((f) | (b))
#define  RESET_FLAG(f,b)                   ((f) & ~(b))
#define  GET_FLAG(f,b)                     ((f) & (b))
#define  GET_PTR(f)                        ((f) >> 3) 
#define  SET_PTR(f)                        ((f) << 3) 
#define  GET_BITS(f)			   ((f) & (0x07))
#define  SET_BITS(f,b)                     ((f) | (b))
#define  RESET_BITS(f,b)                   ((f) | ~(b))
#define  CHECK_BIT(f,b)                    ((f) | (b))
#define  SET_MPTR(f,b)			   (((f)<< 3) | (b))

// for Reset-bit
#define	 GET_FBIT(f)			   ((f) & (0x04))	 
#define  SET_FBIT(f)                       ((f) | (0x04))	
#define  RESET_FBIT(f)                     ((f) & (~0x04))

// for Retain-bit
#define  GET_RBIT(f)                       ((f) & (0x02)) 
#define  SET_RBIT(f)                       ((f) | (0x02)) 
#define  RESET_RBIT(f)                     ((f) & (~0x02))

// for Deletion-bit
#define  GET_DBIT(f)                       ((f) & (0x01)) 
#define  SET_DBIT(f)                       ((f) | (0x01)) 
#define  RESET_DBIT(f)                     ((f) & (~0x01))
 
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
    HTS_REQ_TYPE_ADD    = 0x02,
    HTS_REQ_TYPE_REMOVE = 0x04
  };

enum eRetVals 
  {
    HTS_SUCCESS        = 0,
    HTS_FAILURE        = 1,
    HTS_FATAL_ERROR    = 2,
    HTS_ATTEMPT_FAILED = 3
  };
#endif

