
#ifndef _APPL_CONSTS_HPP_
#define _APPL_CONSTS_HPP_

#define TEST_THREADS         2

enum eOrderType
  {
    TEST_ASCENDING_ORDER   = 0,
    TEST_DESCENDING_ORDER  = 1    
  };

enum eStatus
  {
    TEST_OK               = 0,
    TEST_NOT_OK           = 1,
    TEST_SUBMIT_FAILED    = 2,
    TEST_REQ_ABORTED      = 3,
    TEST_ATTEMPT_FAILED   = 4,
    TEST_OPENCL_ERROR     = 5,    
  };

#endif
