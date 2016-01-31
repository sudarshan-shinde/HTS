#include "HTSOcl.hpp"

/* convert the kernel file into a string */
UINT uiConvertToString(const char *filename, std::string& s)
{
  size_t size;
  char*  str;
  std::fstream f(filename, (std::fstream::in | std::fstream::binary));
  
  if(f.is_open())
    {
      size_t fileSize;
      f.seekg(0, std::fstream::end);
      size = fileSize = (size_t)f.tellg();
      f.seekg(0, std::fstream::beg);
      str = new char[size+1];
      if(!str)
	{
	  f.close();
	  return 0;
	}
      
      f.read(str, fileSize);
      f.close();
      str[size] = '\0';
      s = str;
      delete[] str;
      return HTS_OK;
    }
  
  std::cout << "Error: failed to open file\n:" << filename << std::endl;
  return HTS_NOT_OK;
}

UINT uiGetOCLContext(TOclContext* pOclContext)
{
  /* get the first platform */
  cl_uint        uiNumPlatforms;	
  // Get number of platforms
  cl_int	 iStatus   = clGetPlatformIDs(0, NULL, &uiNumPlatforms);
  if (iStatus != CL_SUCCESS)
    {
      return HTS_NOT_OK;
    }
  //if atleast one platform is there, continue
  if(uiNumPlatforms > 0)
    {
      // Allocate memory, to save platform_id based on number of platforms available 
      cl_platform_id* pPlatforms = new cl_platform_id[uiNumPlatforms];
      // Get platform_id's for existing platforms  
      iStatus                    = clGetPlatformIDs(uiNumPlatforms,
						    pPlatforms,
						    NULL);
      // take only first platform_id
      pOclContext->oclPlatform   = pPlatforms[0];
      // De-allocate memory for local variable 
      delete[] pPlatforms;
    }
  else
    {
      return HTS_NOT_OK;
    }
  
  /* get a GPU device */
  cl_uint	uiNumDevices = 0;
  // Get number of devices available for a specified platform  
  iStatus = clGetDeviceIDs(pOclContext->oclPlatform,
			   CL_DEVICE_TYPE_GPU,
			   0,
			   NULL,
			   &uiNumDevices);
  if(uiNumDevices > 0)
    {
	     
      cl_device_id*  pDevices;
      // Allocate memory for device_id's
      pDevices = new cl_device_id[uiNumDevices];
     // Get device_id's for al devices available  
      iStatus  = clGetDeviceIDs(pOclContext->oclPlatform,
				CL_DEVICE_TYPE_GPU,
				uiNumDevices,
				pDevices,
				NULL);
      // Assining it to global variable 
      pOclContext->pOclDevices = pDevices;

      /* check if the device supports at least coarse grain SVM */
      char     pOclVer[40];
      size_t   uiVerSize;
      
      clGetDeviceInfo(pOclContext->pOclDevices[0],
		      CL_DEVICE_OPENCL_C_VERSION,
		      0,
		      NULL,
		      &uiVerSize);
      
      clGetDeviceInfo(pOclContext->pOclDevices[0],
		      CL_DEVICE_OPENCL_C_VERSION,
		      uiVerSize,
		      pOclVer,
		      NULL);

      std::cout << "Version :" << pOclVer << std::endl;

      cl_device_svm_capabilities tSVMCapabilities;
      size_t                     uiSVMCapSize;
      
      clGetDeviceInfo(pOclContext->pOclDevices[0],
		      CL_DEVICE_SVM_CAPABILITIES,
		      0,
		      NULL,
		      &uiSVMCapSize);
      
      clGetDeviceInfo(pOclContext->pOclDevices[0],
		      CL_DEVICE_SVM_CAPABILITIES,
		      uiSVMCapSize,
		      (void *)(&tSVMCapabilities),
		      NULL);

      if(tSVMCapabilities & CL_DEVICE_SVM_ATOMICS)
	std::cout << "SVM atomics supported." << std::endl;
      else if(tSVMCapabilities & CL_DEVICE_SVM_FINE_GRAIN_BUFFER)
	std::cout << "SVM fine grain buffer supported." << std::endl;
      else if(tSVMCapabilities & CL_DEVICE_SVM_FINE_GRAIN_SYSTEM)
	std::cout << "SVM fine grain system supported." << std::endl;
      else if(tSVMCapabilities & CL_DEVICE_SVM_COARSE_GRAIN_BUFFER)
	std::cout << "SVM coarse grain buffer supported." << std::endl;
    }
  else
    {
      return HTS_NOT_OK;
    }
  
  /* create context */
  pOclContext->oclContext = clCreateContext(NULL,
					    1,
					    pOclContext->pOclDevices,
					    NULL,
					    NULL,
					    NULL);

  /*create command queue */
  cl_command_queue_properties prop[] = {0};
  pOclContext->oclCommandQueue
    = clCreateCommandQueueWithProperties(pOclContext->oclContext,
					 pOclContext->pOclDevices[0],
					 prop,
					 NULL);

  return HTS_OK;
}

UINT uiReleaseOCLContext(TOclContext* pOclContext)
{
  clReleaseCommandQueue(pOclContext->oclCommandQueue);
  clReleaseContext(pOclContext->oclContext);
  return HTS_OK;
}
