module vulkan.debugcallback;

import erupted;

import vulkan.check;


struct DebugCallback
{
  VkDebugReportCallbackEXT debugCallback;
  VkInstance instance;
  
  this(VkInstance instance)
  {
    this.instance = instance;
    
    PFN_vkDebugReportCallbackEXT debugCallbackFunction = (
      uint flags,
      VkDebugReportObjectTypeEXT objectType,
      ulong object,
      ulong location,
      int messageCode,
      const(char)* pLayerPrefix,
      const(char)* pMessage,
      void* pUserData)
    {
      import core.stdc.stdio;
      printf("Validation layer: %s\n", pMessage);
      return VK_FALSE;
    };
  
    VkDebugReportCallbackCreateInfoEXT debugReportCallbackCreateInfo =
    {
      flags: VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT,
      pfnCallback: debugCallbackFunction,
    };
    
    instance.vkCreateDebugReportCallbackEXT(&debugReportCallbackCreateInfo, null, &debugCallback).checkVk;
  }
  
  ~this()
  {
    instance.vkDestroyDebugReportCallbackEXT(debugCallback, null);
  }
}
