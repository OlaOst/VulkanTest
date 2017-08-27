import std.algorithm : all, any, canFind, clamp, countUntil, each, filter, find, map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.range : enumerate;
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
  instance.loadDeviceLevelFunctions();

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

VkPhysicalDevice selectPhysicalDevice(VkInstance instance, VkSurfaceKHR surface, string[] requestedDeviceExtensions)
{ 
  uint deviceCount;
  instance.vkEnumeratePhysicalDevices(&deviceCount, null).checkVk;
  
  enforce(deviceCount > 0, "Could not find any physical devices");
  
  VkPhysicalDevice[] devices;
  devices.length = deviceCount;
  instance.vkEnumeratePhysicalDevices(&deviceCount, devices.ptr);

  auto findSuitableDevice = devices.find!(device => device.isDeviceSuitable(surface, requestedDeviceExtensions));
  enforce(findSuitableDevice.length > 0, "Could not find any suitable physical device");
  return findSuitableDevice[0];
}

bool isDeviceSuitable(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, string[] requestedDeviceExtensions)
{
  VkPhysicalDeviceProperties deviceProperties;
  physicalDevice.vkGetPhysicalDeviceProperties(&deviceProperties);
      
  VkPhysicalDeviceFeatures deviceFeatures;
  physicalDevice.vkGetPhysicalDeviceFeatures(&deviceFeatures);
  
  auto queueFamilyIndices = physicalDevice.getQueueFamilyIndices(surface);
  
  if (requestedDeviceExtensions.length > 0)
  {
    return queueFamilyIndices.isComplete() && 
           physicalDevice.checkDeviceExtensionSupport(requestedDeviceExtensions) && 
           physicalDevice.querySwapChainSupport(surface).isAdequate;
  }
  else
  {
    return queueFamilyIndices.isComplete() && 
           physicalDevice.checkDeviceExtensionSupport(requestedDeviceExtensions);
  }
}

bool checkDeviceExtensionSupport(VkPhysicalDevice physicalDevice, string[] requestedExtensions)
{
  uint extensionCount;
  physicalDevice.vkEnumerateDeviceExtensionProperties(null, &extensionCount, null).checkVk;
  
  VkExtensionProperties[] availableExtensions;
  availableExtensions.length = extensionCount;
  physicalDevice.vkEnumerateDeviceExtensionProperties(null, &extensionCount, availableExtensions.ptr);
    
  return requestedExtensions.all!(requestedExtensionName => availableExtensions.any!(availableExtension => requestedExtensionName == availableExtension.extensionName.ptr.fromStringz));  
}

struct QueueFamilyIndices
{
  int drawingFamilyIndex = -1;
  int presentationFamilyIndex = -1;
  
  bool isComplete()
  {
    return drawingFamilyIndex >= 0 &&
           presentationFamilyIndex >= 0;
  }
}

QueueFamilyIndices getQueueFamilyIndices(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
  uint queueFamilyCount;
  physicalDevice.vkGetPhysicalDeviceQueueFamilyProperties(&queueFamilyCount, null);
  
  VkQueueFamilyProperties[] queueFamilies;
  queueFamilies.length = queueFamilyCount;
  physicalDevice.vkGetPhysicalDeviceQueueFamilyProperties(&queueFamilyCount, queueFamilies.ptr);
  
  QueueFamilyIndices queueFamilyIndices;
  foreach (uint index, queueFamily; queueFamilies.filter!(queueFamily => queueFamily.queueCount > 0).array)
  {
    if (queueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT)
      queueFamilyIndices.drawingFamilyIndex = cast(int)index;
      
    VkBool32 presentationSupport = false;
    physicalDevice.vkGetPhysicalDeviceSurfaceSupportKHR(index, surface, &presentationSupport).checkVk;
    
    if (presentationSupport)
      queueFamilyIndices.presentationFamilyIndex = cast(int)index;    
  }
  return queueFamilyIndices;
}

VkDevice createLogicalDevice(VkPhysicalDevice physicalDevice, QueueFamilyIndices queueFamilyIndices, string[] requestedExtensionNames, string[] requestedValidationLayers)
{
  auto queuePriority = 1.0f;
  VkDeviceQueueCreateInfo drawingQueueCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndices.drawingFamilyIndex,
    queueCount: 1,
    pQueuePriorities: &queuePriority,
  };
  
  auto queueCreateInfos = [drawingQueueCreateInfo];
  
  if (queueFamilyIndices.drawingFamilyIndex != queueFamilyIndices.presentationFamilyIndex)
  {
    VkDeviceQueueCreateInfo presentationQueueCreateInfo =
    {
      sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex: queueFamilyIndices.presentationFamilyIndex,
      queueCount: 1,
      pQueuePriorities: &queuePriority,
    };
    
    queueCreateInfos ~= presentationQueueCreateInfo;
  }
  
  VkPhysicalDeviceFeatures deviceFeatures =
  {
    // no features wanted yet
  };
  
  VkDeviceCreateInfo logicalDeviceCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pQueueCreateInfos: queueCreateInfos.ptr,
    queueCreateInfoCount: cast(uint)queueCreateInfos.length,
    pEnabledFeatures: &deviceFeatures,
    
    enabledExtensionCount: cast(uint)requestedExtensionNames.length,
    ppEnabledExtensionNames: requestedExtensionNames.map!(extension => extension.toStringz).array.ptr,
    
    enabledLayerCount: cast(uint)requestedValidationLayers.length,
    ppEnabledLayerNames: requestedValidationLayers.map!(layer => layer.toStringz).array.ptr,
  };
    
  VkDevice logicalDevice;
  physicalDevice.vkCreateDevice(&logicalDeviceCreateInfo, null, &logicalDevice).checkVk;
  
  logicalDevice.loadDeviceLevelFunctions();
      
  return logicalDevice;
}

VkQueue createDrawingQueue(VkDevice logicalDevice, QueueFamilyIndices queueFamilyIndices)
{
  VkQueue graphicsQueue;
  logicalDevice.vkGetDeviceQueue(queueFamilyIndices.drawingFamilyIndex, 0, &graphicsQueue);
  return graphicsQueue;
}

VkQueue createPresentationQueue(VkDevice logicalDevice, QueueFamilyIndices queueFamilyIndices)
{
  VkQueue presentationQueue;
  logicalDevice.vkGetDeviceQueue(queueFamilyIndices.presentationFamilyIndex, 0, &presentationQueue);
  return presentationQueue;
}

VkSurfaceKHR createSurface(VkInstance instance, SDL_Window* window)
{
  SDL_SysWMinfo wminfo;
  //SDL_VERSION(&wminfo.version_); // compiled version
  SDL_GetVersion(&wminfo.version_); // linked version
  enforce(SDL_GetWindowWMInfo(window, &wminfo) != SDL_FALSE, "Failed to get window info from SDL: " ~ SDL_GetError().to!string);

  VkSurfaceKHR surface;

  version(linux)
  {
    VkXcbSurfaceCreateInfoKHR surfaceCreateInfo =
    {
      sType: VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
      connection: xcb_connect(null, null),
      window: wminfo.info.x11.window,
    };
    
    instance.vkCreateXcbSurfaceKHR(&surfaceCreateInfo, null, &surface).checkVk;
  }
  else
  {
    assert(0, "This platform is not supported yet");
  }
  
  return surface;
}

struct SwapChainSupportDetails
{
  VkSurfaceCapabilitiesKHR capabilities;
  VkSurfaceFormatKHR[] formats;
  VkPresentModeKHR[] presentModes;
  
  bool isAdequate()
  {
    return formats.length > 0 && presentModes.length > 0;
  }
}

SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
  SwapChainSupportDetails details;
  
  physicalDevice.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(surface, &details.capabilities).checkVk;
  
  uint formatCount;
  physicalDevice.vkGetPhysicalDeviceSurfaceFormatsKHR(surface, &formatCount, null);
  
  details.formats.length = formatCount;
  physicalDevice.vkGetPhysicalDeviceSurfaceFormatsKHR(surface, &formatCount, details.formats.ptr);
  
  uint presentModeCount;
  physicalDevice.vkGetPhysicalDeviceSurfacePresentModesKHR(surface, &presentModeCount, null);
  
  details.presentModes.length = presentModeCount;
  physicalDevice.vkGetPhysicalDeviceSurfacePresentModesKHR(surface, &presentModeCount, details.presentModes.ptr);
  
  return details;
}

VkSurfaceFormatKHR chooseSwapSurfaceFormat(VkSurfaceFormatKHR[] availableFormats)
{
  if (availableFormats.length == 1 && availableFormats[0].format == VK_FORMAT_UNDEFINED)
  {
    return VkSurfaceFormatKHR(VK_FORMAT_B8G8R8A8_UNORM, 
                              VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
  }
  else
  {
    auto wantedFormatSearch = availableFormats.find!(availableFormat => availableFormat.format == VK_FORMAT_B8G8R8A8_UNORM && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
    
    if (wantedFormatSearch.length == 0)
    {
      return availableFormats[0];
    }
    else
    {
      return wantedFormatSearch[0];
    }
  }
}

VkPresentModeKHR chooseSwapPresentMode(VkPresentModeKHR[] availablePresentModes)
{
  auto desiredPresentModes = [VK_PRESENT_MODE_MAILBOX_KHR,
                              VK_PRESENT_MODE_IMMEDIATE_KHR,
                              VK_PRESENT_MODE_FIFO_KHR];
  
  foreach(desiredPresentMode; desiredPresentModes)
  {
    if (availablePresentModes.canFind(desiredPresentMode))
      return desiredPresentMode;
  }

  scope(failure)
  {
    writeln("Could not find any desired present modes ", desiredPresentModes, " among available present modes ", availablePresentModes);
  }
  
  assert(0);
}

VkExtent2D chooseSwapExtent(VkSurfaceCapabilitiesKHR capabilities)
{
  if (capabilities.currentExtent.width != uint.max)
  {
    return capabilities.currentExtent;
  }
  else
  {
    auto width = 800;
    auto height = 600;
    
    VkExtent2D actualExtent =
    {
      width: width.clamp(capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
      height: height.clamp(capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
    
    return actualExtent;
  }
}

VkSwapchainKHR createSwapchain(VkDevice logicalDevice, VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, QueueFamilyIndices queueFamilyIndices)
{
  auto swapChainSupport = physicalDevice.querySwapChainSupport(surface);
  
  auto surfaceFormat = swapChainSupport.formats.chooseSwapSurfaceFormat();
  auto presentMode = swapChainSupport.presentModes.chooseSwapPresentMode();
  auto extent = swapChainSupport.capabilities.chooseSwapExtent;
  
  uint imageCount = swapChainSupport.capabilities.minImageCount + 1;
  if (swapChainSupport.capabilities.maxImageCount > 0 && imageCount > swapChainSupport.capabilities.maxImageCount)
    imageCount = swapChainSupport.capabilities.maxImageCount;
    
  VkSwapchainCreateInfoKHR swapChainCreateInfo =
  {
    sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    surface: surface,
    minImageCount: imageCount,
    imageFormat: surfaceFormat.format,
    imageColorSpace: surfaceFormat.colorSpace,
    imageExtent: extent,
    imageArrayLayers: 1,
    imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

    preTransform: swapChainSupport.capabilities.currentTransform,
    compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    presentMode: presentMode,
    clipped: VK_TRUE,
    oldSwapchain: VK_NULL_HANDLE,
  };
    
  if (queueFamilyIndices.drawingFamilyIndex != queueFamilyIndices.presentationFamilyIndex)
  {
    swapChainCreateInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
    swapChainCreateInfo.queueFamilyIndexCount = 2;
    
    auto indices = [queueFamilyIndices.drawingFamilyIndex, queueFamilyIndices.presentationFamilyIndex];

    swapChainCreateInfo.pQueueFamilyIndices = cast(const(uint)*)indices.ptr;
  }
  else
  {
    swapChainCreateInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    swapChainCreateInfo.queueFamilyIndexCount = 0;
    swapChainCreateInfo.pQueueFamilyIndices = null;
  }
  
  VkSwapchainKHR swapChain;
  logicalDevice.vkCreateSwapchainKHR(&swapChainCreateInfo, null, &swapChain).checkVk;
  return swapChain;
}

void main()
{
  string[] requestedExtensions = ["VK_KHR_surface"];
  version(linux) requestedExtensions ~= ["VK_KHR_xcb_surface"];
  debug requestedExtensions ~= ["VK_EXT_debug_report"];

  string[] requestedValidationLayers;
  debug requestedValidationLayers ~= ["VK_LAYER_LUNARG_standard_validation"];
    
  auto instance = createVulkanInstance(requestedExtensions, requestedValidationLayers);
  scope(exit) vkDestroyInstance(instance, null);

  auto debugCallback = instance.createDebugCallback();
  scope(exit) instance.vkDestroyDebugReportCallbackEXT(debugCallback, null);

  auto window = createSDLWindow();

  auto surface = instance.createSurface(window);
  scope(exit) instance.vkDestroySurfaceKHR(surface, null);

  auto requestedDeviceExtensions = ["VK_KHR_swapchain"];

  auto physicalDevice = instance.selectPhysicalDevice(surface, requestedDeviceExtensions);

  auto queueFamilyIndices = physicalDevice.getQueueFamilyIndices(surface);
    
  auto logicalDevice = physicalDevice.createLogicalDevice(queueFamilyIndices, requestedDeviceExtensions, requestedValidationLayers);
  scope(exit) logicalDevice.vkDestroyDevice(null);

  auto drawingQueue = logicalDevice.createDrawingQueue(queueFamilyIndices);
  auto presentationQueue = logicalDevice.createPresentationQueue(queueFamilyIndices);
  
  auto swapchain = logicalDevice.createSwapchain(physicalDevice, surface, queueFamilyIndices);
  scope(exit) logicalDevice.vkDestroySwapchainKHR(swapchain, null);
  
  //writeln("Available extensions:");
  //instance.getAvailableExtensions.map!(ext => ext.extensionName).each!writeln;

  //writeln("\nAvailable layers:");
  //instance.getAvailableLayers.map!(layer => layer.layerName).each!writeln;

  debug
  {    
    enforce(instance.checkValidationLayerSupport(requestedValidationLayers),
            "Could not find requested validation layers " ~ requestedValidationLayers.to!string ~ " in available layers " ~ instance.getAvailableLayers().map!(layer => layer.layerName.ptr.fromStringz).to!string);
  }  
}
