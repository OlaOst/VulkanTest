module vulkan.instance;

import std.algorithm : map;
import std.array : array;
import std.string : toStringz;

import erupted;

import vulkan.check;


VkInstance createVulkanInstance(string applicationName, string[] requestedExtensions, string[] requestedLayers)
{
  DerelictErupted.load();
  
  VkApplicationInfo appInfo =
  {
    pApplicationName: applicationName.ptr,
    
  };
  
  VkInstanceCreateInfo instanceCreateInfo =
  {
    enabledExtensionCount: cast(uint)requestedExtensions.length,
    ppEnabledExtensionNames: requestedExtensions.map!(extensionName => extensionName.toStringz).array.ptr,
    
    enabledLayerCount: cast(uint)requestedLayers.length,
    ppEnabledLayerNames: requestedLayers.map!(layerName => layerName.toStringz).array.ptr,
  };
  
  VkInstance instance;
  vkCreateInstance(&instanceCreateInfo, null, &instance).checkVk;
  
  instance.loadInstanceLevelFunctions();
  instance.loadDeviceLevelFunctions();
  
  return instance;
}
