module vulkan.instance;

import std.algorithm : map;
import std.array : array;
import std.string : fromStringz, toStringz;

import erupted;

import vulkan.check;
import vulkan.debugcallback;


struct Instance
{
  VkInstance instance;
  alias instance this;
  
  DebugCallback debugCallback;
  
  
  this(string applicationName, string[] requestedExtensions, string[] requestedLayers)
  {
    DerelictErupted.load();
    
    VkApplicationInfo appInfo =
    {
      pApplicationName: applicationName.ptr,
      applicationVersion: VK_MAKE_VERSION(1, 0, 0),
     
      pEngineName: (applicationName ~ "Engine").ptr,
      engineVersion: VK_MAKE_VERSION(1, 0, 0),
     
      apiVersion: VK_API_VERSION_1_0,
    };
   
    VkInstanceCreateInfo instanceCreateInfo =
    {
      enabledExtensionCount: cast(uint)requestedExtensions.length,
      ppEnabledExtensionNames: requestedExtensions.map!(extensionName => extensionName.toStringz).array.ptr,
     
      enabledLayerCount: cast(uint)requestedLayers.length,
      ppEnabledLayerNames: requestedLayers.map!(layerName => layerName.toStringz).array.ptr,
    };
   
    vkCreateInstance(&instanceCreateInfo, null, &instance).checkVk;
   
    instance.loadInstanceLevelFunctions();
    instance.loadDeviceLevelFunctions();
    
    debug debugCallback = DebugCallback(instance);
  }
  
  ~this()
  {
    debug debugCallback.__dtor();
    vkDestroyInstance(instance, null);
  }
  
  auto getAvailableExtensionNames()
  {
    uint extensionCount;
    vkEnumerateInstanceExtensionProperties(null, &extensionCount, null).checkVk;
    
    VkExtensionProperties[] extensions;
    extensions.length = extensionCount;
    vkEnumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr).checkVk;
    
    return extensions.map!(extension => extension.extensionName.ptr.fromStringz.dup);
  }
  
  auto getAvailableLayerNames()
  {
    uint layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, null).checkVk;
    
    VkLayerProperties[] layers;
    layers.length = layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, layers.ptr).checkVk;
    
    return layers.map!(layer => layer.layerName.ptr.fromStringz.dup);
  }  
}
