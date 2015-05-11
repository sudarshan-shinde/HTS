#include <iostream>
#include <fstream>
#include "HTSOcl.hpp"
#include "HTSFrontEnd.hpp"

//const char* pProgramFile = "HTSKernels.cl";

int main()
{
  //get OCL context
  TOclContext tOclContext;

  if (uiGetOCLContext(&tOclContext) != HTS_OK)
    {
      std::cout << "failed to initialize OCL context" << std::endl;
      return -1;
    }

  std::cout << "OCL context initialization successful..." << std::endl;

  //get the front end 
  CFrontEnd tFrontEnd;
  TFid  tFid = tFrontEnd.tRegister();
  
  cl_uint uiNoThreads = tFrontEnd.uiGetThreadCount();

  std::cout << "Threads:" << uiNoThreads << std::endl;

  tFrontEnd.uiDeRegister(tFid);
  
  uiReleaseOCLContext(&tOclContext);
  return 0;
}
