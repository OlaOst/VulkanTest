import std.algorithm : all, any, countUntil, each, filter, find, map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.stdio : writeln;
import std.string : fromStringz, toStringz;

import derelict.sdl2.sdl;
import erupted;


private void checkVk(VkResult result)
{
  enforce(result == VK_SUCCESS, result.to!string);
}

VkInstance createVulkanInstance(string[] requestedExtensions, string[] requestedValidationLayers)
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
    
    enabledExtensionCount: cast(uint)requestedExtensions.length,
    ppEnabledExtensionNames: requestedExtensions.map!(extension => extension.toStringz).array.ptr,

    enabledLayerCount: cast(uint)requestedValidationLayers.length,
    ppEnabledLayerNames: requestedValidationLayers.map!(layer => layer.toStringz).array.ptr,
  };
  
  VkInstance instance;
  vkCreateInstance(&createInfo, null, &instance).checkVk;

  instance.loadInstanceLevelFunctions();

  return instance;
}

VkExtensionProperties[] getAvailableExtensions(VkInstance instance)
{  
  uint extensionCount;
  vkEnumerateInstanceExtensionProperties(null, &extensionCount, null).checkVk;
    
  VkExtensionProperties[] extensions;
  extensions.length = extensionCount;
  vkEnumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr).checkVk;
  
  return extensions;
}

VkLayerProperties[] getAvailableLayers(VkInstance instance)
{
  uint layerCount;
  vkEnumerateInstanceLayerProperties(&layerCount, null).checkVk;
  
  VkLayerProperties[] availableLayers;
  availableLayers.length = layerCount;
  
  vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr).checkVk;
  
  return availableLayers;
}

bool checkValidationLayerSupport(VkInstance instance, string[] requestedValidationLayers)
{
  auto availableValidationLayers = instance.getAvailableLayers();
  return requestedValidationLayers.all!(requestedValidationLayerName => availableValidationLayers.any!(availableValidationLayer => requestedValidationLayerName == availableValidationLayer.layerName.ptr.fromStringz));
}

SDL_Window* createSDLWindow()
{
  DerelictSDL2.load(SharedLibVersion(2, 0, 4));
  
  enforce(SDL_Init(SDL_INIT_VIDEO) == 0, "Failed to initialize SDL: " ~ SDL_GetError().to!string);
  
  auto window = SDL_CreateWindow("VulkanTest",
                                 SDL_WINDOWPOS_CENTERED,
                                 SDL_WINDOWPOS_CENTERED,
                                 800,
                                 600,
                                 SDL_WINDOW_SHOWN);

  enforce(window !is null, "Error creating window: " ~ SDL_GetError().to!string);
  
  SDL_SysWMinfo info;
  //SDL_VERSION(&info.version_); // compiled version
  SDL_GetVersion(&info.version_); // linked version
  enforce(SDL_GetWindowWMInfo(window, &info) != SDL_FALSE, "Failed to get window info from SDL: " ~ SDL_GetError().to!string);  
  
  return window;
}

VkDebugReportCallbackEXT createDebugCallback(VkInstance instance)
{
  PFN_vkDebugReportCallbackEXT debugCallback = (uint flags, 
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
  
  VkDebugReportCallbackCreateInfoEXT createInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
    flags: (VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT),
    pfnCallback: debugCallback,
  };
  
  VkDebugReportCallbackEXT callback;
  instance.vkCreateDebugReportCallbackEXT(&createInfo, null, &callback).checkVk;
  
  return callback;
}

VkPhysicalDevice selectPhysicalDevice(VkInstance instance)
{ 
  uint deviceCount;
  instance.vkEnumeratePhysicalDevices(&deviceCount, null).checkVk;
  
  enforce(deviceCount > 0, "Could not find any physical devices");
  
  VkPhysicalDevice[] devices;
  devices.length = deviceCount;
  instance.vkEnumeratePhysicalDevices(&deviceCount, devices.ptr);

  auto findSuitableDevice = devices.find!(device => device.isDeviceSuitable);
  enforce(findSuitableDevice.length > 0, "Could not find any suitable physical device");
  return findSuitableDevice[0];
}

bool isDeviceSuitable(VkPhysicalDevice device)
{
  VkPhysicalDeviceProperties deviceProperties;
  device.vkGetPhysicalDeviceProperties(&deviceProperties);
      
  VkPhysicalDeviceFeatures deviceFeatures;
  device.vkGetPhysicalDeviceFeatures(&deviceFeatures);
  
  auto queueFamilyIndex = device.getQueueFamilyIndex();
  
  return queueFamilyIndex >= 0;
}

uint getQueueFamilyIndex(VkPhysicalDevice device)
{
  uint queueFamilyCount;
  vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
  
  VkQueueFamilyProperties[] queueFamilies;
  queueFamilies.length = queueFamilyCount;
  vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
  
  //auto queueFamiliesWithGraphics = queueFamilies.filter!(queueFamily => queueFamily.queueCount > 0 && queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT);
  //enforce(!queueFamiliesWithGraphics.empty, "Could not find any queue family with graphics bit enabled");  
  //return queueFamiliesWithGraphics.array;
  
  auto queueFamilyIndex = queueFamilies.countUntil!(queueFamily => queueFamily.queueCount > 0 && queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT);
  enforce(queueFamilyIndex != -1);
  return cast(uint)queueFamilyIndex;
}

VkDevice createLogicalDevice(VkPhysicalDevice physicalDevice, string[] requestedValidationLayers)
{
  auto queueFamilyIndex = physicalDevice.getQueueFamilyIndex();
  auto queuePriority = 1.0f;
  VkDeviceQueueCreateInfo queueCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndex,
    queueCount: 1,
    pQueuePriorities: &queuePriority,
  };
  
  VkPhysicalDeviceFeatures deviceFeatures =
  {
    // no features wanted yet
  };
  
  VkDeviceCreateInfo deviceCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pQueueCreateInfos: &queueCreateInfo,
    queueCreateInfoCount: 1,
    pEnabledFeatures: &deviceFeatures,
    
    enabledExtensionCount: 0,
    
    enabledLayerCount: cast(uint)requestedValidationLayers.length,
    ppEnabledLayerNames: requestedValidationLayers.map!(layer => layer.toStringz).array.ptr,
  };
  
  VkDevice device;
  physicalDevice.vkCreateDevice(&deviceCreateInfo, null, &device).checkVk;
  
  return device;
}

void main()
{
  auto window = createSDLWindow();

  string[] requestedExtensions;  
  debug requestedExtensions ~= ["VK_EXT_debug_report"];

  string[] requestedValidationLayers;
  debug requestedValidationLayers ~= ["VK_LAYER_LUNARG_standard_validation"];
    
  auto instance = createVulkanInstance(requestedExtensions, requestedValidationLayers);
  auto debugCallback = instance.createDebugCallback();
      
  auto physicalDevice = instance.selectPhysicalDevice();
  
  auto logicalDevice = physicalDevice.createLogicalDevice(requestedValidationLayers);
  
  //writeln("Available extensions:");
  //instance.getAvailableExtensions.map!(ext => ext.extensionName).each!writeln;

  //writeln("\nAvailable layers:");
  //instance.getAvailableLayers.map!(layer => layer.layerName).each!writeln;

  debug
  {    
    enforce(instance.checkValidationLayerSupport(requestedValidationLayers),
            "Could not find requested validation layers " ~ requestedValidationLayers.to!string ~ " in available layers " ~ instance.getAvailableLayers().map!(layer => layer.layerName.ptr.fromStringz).to!string);
  }
  
  logicalDevice.vkDestroyDevice(null);
  instance.vkDestroyDebugReportCallbackEXT(debugCallback, null);
  vkDestroyInstance(instance, null);
}
