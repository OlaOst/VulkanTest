import std.stdio : writeln;

import erupted;


private void checkVk(VkResult result)
{
  import std.conv : to;
  import std.exception : enforce;
  enforce(result == VK_SUCCESS, result.to!string);
}

VkInstance initVulkan()
{
  DerelictErupted.load();

  VkApplicationInfo appInfo =
  {
    sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
    pApplicationName: "Vulkan Test",
    applicationVersion: VK_MAKE_VERSION(1, 0, 0),
    pEngineName: "No engine",
    engineVersion: VK_MAKE_VERSION(1, 0, 0),
    apiVersion: VK_API_VERSION_1_0,
  };
  
  VkInstanceCreateInfo createInfo =
  {
    sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    pApplicationInfo: &appInfo,
    
    //enabledExtensionCount: ?,
    //ppEnableExtensionNames: ?,
    enabledLayerCount: 0,
  };
  
  VkInstance instance;
  vkCreateInstance(&createInfo, null, &instance).checkVk;
  
  uint extensionCount;
  vkEnumerateInstanceExtensionProperties(null, &extensionCount, null).checkVk;
    
  VkExtensionProperties[] extensions;
  extensions.length = extensionCount;
  vkEnumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr).checkVk;
  
  import std.algorithm;
  extensions.map!(ext => ext.extensionName).each!writeln;
  
  return instance;
}

void main()
{
  auto instance = initVulkan();
  
  vkDestroyInstance(instance, null);
}
