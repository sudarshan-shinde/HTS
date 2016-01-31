#ifndef _HTS_OCL_HPP_
#define _HTS_OCL_HPP_

#include <CL/cl.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <iostream>
#include <string>
#include <fstream>

#include "HTSConsts.hpp"

typedef struct SOclContext
{
public:
  cl_platform_id      oclPlatform;
  cl_context          oclContext;
  cl_device_id*       pOclDevices;
  cl_command_queue    oclCommandQueue;
} TOclContext;

UINT  uiConvertToString(const char *filename, std::string& s);
UINT  uiGetOCLContext(TOclContext* pOclContext);
UINT  uiReleaseOCLContext(TOclContext* pOclContext);

#endif
